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
        guard AXIsProcessTrusted() else {
            return AutoPasteOutcome(
                pasted: false,
                method: .unavailable,
                detail: "accessibility permission is missing."
            )
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AutoPasteOutcome(
                pasted: false,
                method: .unavailable,
                detail: "transcript was empty."
            )
        }

        let target = resolveTargetApplication(
            targetBundleID: targetBundleID,
            targetPID: targetPID,
            ownBundleID: ownBundleID
        )

        if shouldPasteIntoCurrentFrontmost(target: target, ownBundleID: ownBundleID) {
            pasteWithBestEffortKeyboard(text: text)
            return AutoPasteOutcome(
                pasted: true,
                method: .keyboardPasteAttempt,
                detail: "sent command-v to the currently focused app."
            )
        }

        if let target {
            target.activate(options: [.activateAllWindows])
            try? await Task.sleep(nanoseconds: 250_000_000)

            if insertWithAccessibility(text, into: target.processIdentifier) {
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
                    detail: "pasted with command-v into the focused target app."
                )
            }

            await pasteWithBestEffortKeyboard(text: text, into: target)
            return AutoPasteOutcome(
                pasted: true,
                method: .keyboardPasteAttempt,
                detail: "sent command-v to the original target app."
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        target.activate(options: [.activateAllWindows])
        try? await Task.sleep(nanoseconds: 180_000_000)

        postCommandVGlobally()
        try? await Task.sleep(nanoseconds: 180_000_000)
        if focusedTargetValueContains(text, processIdentifier: target.processIdentifier) {
            return true
        }

        if postCommandVWithSystemEvents(processIdentifier: target.processIdentifier) {
            try? await Task.sleep(nanoseconds: 180_000_000)
            return focusedTargetValueContains(text, processIdentifier: target.processIdentifier)
        }

        return false
    }

    private func pasteWithBestEffortKeyboard(text: String, into target: NSRunningApplication) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        target.activate(options: [.activateAllWindows])
        try? await Task.sleep(nanoseconds: 220_000_000)
        postCommandVGlobally()
    }

    private func pasteWithBestEffortKeyboard(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        postCommandVGlobally()
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
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            return
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
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
