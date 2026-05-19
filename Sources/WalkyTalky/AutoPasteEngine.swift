import AppKit
import ApplicationServices

struct AutoPasteOutcome: Equatable {
    enum Method: String {
        case accessibilityInsert = "accessibility insert"
        case keyboardPaste = "keyboard paste"
        case keyboardPasteAttempt = "keyboard paste attempt"
        case unavailable = "unavailable"
    }

    let pasted: Bool
    let method: Method
    let detail: String
}

@MainActor
struct AutoPasteEngine {
    func paste(
        text: String,
        targetBundleID: String?,
        targetPID: pid_t?,
        ownBundleID: String?
    ) async -> AutoPasteOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AutoPasteOutcome(
                pasted: false,
                method: .unavailable,
                detail: "transcript was empty."
            )
        }

        guard AXIsProcessTrusted() else {
            requestAccessibilityPrompt()
            writePlainText(text)
            return AutoPasteOutcome(
                pasted: false,
                method: .unavailable,
                detail: "accessibility permission is required for auto paste."
            )
        }

        let target = resolveTargetApplication(
            targetBundleID: targetBundleID,
            targetPID: targetPID,
            ownBundleID: ownBundleID
        )
        let effectiveTarget = target ?? currentExternalFrontmostApplication(ownBundleID: ownBundleID)

        if shouldPasteIntoCurrentFrontmost(target: effectiveTarget, ownBundleID: ownBundleID) {
            await pasteWithBestEffortKeyboard(text: text, restoresClipboard: true)
            return AutoPasteOutcome(
                pasted: true,
                method: .keyboardPasteAttempt,
                detail: "sent command-v to the currently focused app and restored the clipboard."
            )
        }

        if let target = effectiveTarget {
            target.activate(options: [.activateAllWindows])
            try? await Task.sleep(nanoseconds: 250_000_000)

            if AXIsProcessTrusted(), insertWithAccessibility(text, into: target.processIdentifier) {
                return AutoPasteOutcome(
                    pasted: true,
                    method: .accessibilityInsert,
                    detail: "pasted directly into focused text field."
                )
            }

            if await pasteWithKeyboard(text: text, into: target) {
                return AutoPasteOutcome(
                    pasted: true,
                    method: .keyboardPaste,
                    detail: "pasted with command-v and restored the clipboard."
                )
            }

            await pasteWithBestEffortKeyboard(text: text, into: target)
            return AutoPasteOutcome(
                pasted: true,
                method: .keyboardPasteAttempt,
                detail: "sent command-v to the original target app and restored the clipboard."
            )
        }

        return AutoPasteOutcome(
            pasted: false,
            method: .unavailable,
            detail: "copied, but the original target app was not available or did not accept direct paste."
        )
    }

    private func resolveTargetApplication(
        targetBundleID: String?,
        targetPID: pid_t?,
        ownBundleID: String?
    ) -> NSRunningApplication? {
        if let targetPID, let app = NSRunningApplication(processIdentifier: targetPID), !app.isTerminated {
            return app
        }

        if let targetBundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundleID && !$0.isTerminated }) {
            return app
        }

        return nil
    }

    private func currentExternalFrontmostApplication(ownBundleID: String?) -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != ownBundleID,
              frontmost.activationPolicy == .regular,
              !frontmost.isTerminated else {
            return nil
        }
        return frontmost
    }

    private func shouldPasteIntoCurrentFrontmost(target: NSRunningApplication?, ownBundleID: String?) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != ownBundleID else {
            return false
        }

        guard let target else {
            return true
        }

        return frontmost.processIdentifier == target.processIdentifier
            || frontmost.bundleIdentifier == target.bundleIdentifier
    }

    private func insertWithAccessibility(_ text: String, into processIdentifier: pid_t) -> Bool {
        let marker = text
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedStatus == .success, let focusedElement = focusedValue else {
            return false
        }

        let element = focusedElement as! AXUIElement
        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            return focusedElementValueContains(marker, element: element)
        }

        var selectedRangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )
        var currentValue: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )

        guard
            rangeStatus == .success,
            valueStatus == .success,
            let selectedRangeValue,
            let currentText = currentValue as? String
        else {
            return false
        }

        var range = CFRange()
        guard AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &range) else {
            return false
        }

        let currentNSString = currentText as NSString
        let safeLocation = max(0, min(range.location, currentNSString.length))
        let safeLength = max(0, min(range.length, currentNSString.length - safeLocation))
        let updated = currentNSString.replacingCharacters(in: NSRange(location: safeLocation, length: safeLength), with: text)
        let nextCursor = safeLocation + (text as NSString).length

        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFString) == .success else {
            return false
        }

        var nextRange = CFRange(location: nextCursor, length: 0)
        if let nextRangeValue = AXValueCreate(.cfRange, &nextRange) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, nextRangeValue)
        }

        return focusedElementValueContains(marker, element: element)
    }

    private func focusedElementValueContains(_ text: String, element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let currentText = value as? String else {
            return false
        }
        return currentText.contains(text)
    }

    private func pasteWithKeyboard(text: String, into target: NSRunningApplication) async -> Bool {
        let snapshot = PasteboardSnapshot.capture()
        writePlainText(text)

        target.activate(options: [.activateAllWindows])
        try? await Task.sleep(nanoseconds: 180_000_000)

        postCommandVGlobally()
        try? await Task.sleep(nanoseconds: 180_000_000)
        if focusedTargetValueContains(text, processIdentifier: target.processIdentifier) {
            await restoreClipboard(snapshot)
            return true
        }

        if postCommandVWithSystemEvents(processIdentifier: target.processIdentifier) {
            try? await Task.sleep(nanoseconds: 180_000_000)
            let pasted = focusedTargetValueContains(text, processIdentifier: target.processIdentifier)
            if pasted {
                await restoreClipboard(snapshot)
            }
            return pasted
        }

        snapshot.restore()
        return false
    }

    private func pasteWithBestEffortKeyboard(text: String, into target: NSRunningApplication) async {
        let snapshot = PasteboardSnapshot.capture()
        writePlainText(text)
        target.activate(options: [.activateAllWindows])
        try? await Task.sleep(nanoseconds: 220_000_000)
        postCommandVGlobally()
        await restoreClipboard(snapshot)
    }

    private func pasteWithBestEffortKeyboard(text: String, restoresClipboard: Bool = false) async {
        let snapshot = restoresClipboard ? PasteboardSnapshot.capture() : nil
        writePlainText(text)
        postCommandVGlobally()
        if let snapshot {
            await restoreClipboard(snapshot)
        }
    }

    private func focusedTargetValueContains(_ text: String, processIdentifier: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else {
            return false
        }
        return focusedElementValueContains(text, element: focusedValue as! AXUIElement)
    }

    private func postCommandVGlobally() {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        usleep(8_000)
        keyUp.post(tap: .cgSessionEventTap)
        usleep(20_000)
    }

    private func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func writePlainText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func restoreClipboard(_ snapshot: PasteboardSnapshot) async {
        try? await Task.sleep(nanoseconds: 650_000_000)
        snapshot.restore()
    }

    private func postCommandVWithSystemEvents(processIdentifier: pid_t) -> Bool {
        let source = """
        tell application "System Events"
            set targetProcess to first application process whose unix id is \(processIdentifier)
            set frontmost of targetProcess to true
            delay 0.08
            keystroke "v" using command down
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture() -> PasteboardSnapshot {
        let captured: [[NSPasteboard.PasteboardType: Data]] = NSPasteboard.general.pasteboardItems?.map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        } ?? []
        return PasteboardSnapshot(items: captured)
    }

    func restore() {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        NSPasteboard.general.writeObjects(restoredItems)
    }
}
