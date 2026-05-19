import AppKit
import ApplicationServices

struct AutoPasteOutcome: Equatable {
    enum Method: String {
        case accessibilityInsert = "accessibility insert"
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

        if let target {
            target.activate(options: [.activateAllWindows])
            try? await Task.sleep(nanoseconds: 180_000_000)

            if insertWithAccessibility(text, into: target.processIdentifier) {
                return AutoPasteOutcome(
                    pasted: true,
                    method: .accessibilityInsert,
                    detail: "pasted directly into focused text field."
                )
            }
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

    private func insertWithAccessibility(_ text: String, into processIdentifier: pid_t) -> Bool {
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
            return true
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

        let safeLocation = max(0, min(range.location, currentText.count))
        let safeLength = max(0, min(range.length, currentText.count - safeLocation))
        let start = currentText.index(currentText.startIndex, offsetBy: safeLocation)
        let end = currentText.index(start, offsetBy: safeLength)
        let updated = currentText.replacingCharacters(in: start..<end, with: text)
        let nextCursor = safeLocation + text.count

        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFString) == .success else {
            return false
        }

        var nextRange = CFRange(location: nextCursor, length: 0)
        if let nextRangeValue = AXValueCreate(.cfRange, &nextRange) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, nextRangeValue)
        }

        return true
    }
}
