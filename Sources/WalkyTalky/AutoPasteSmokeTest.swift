import AppKit

@MainActor
enum AutoPasteSmokeTest {
    static func accessibilityStatus() -> Int32 {
        let trusted = AXIsProcessTrusted()
        print("accessibility_trusted=\(trusted)")
        return trusted ? 0 : 2
    }

    static func run(arguments: [String]) async -> Int32 {
        let text = value(after: "--text", in: arguments) ?? "walky talky auto paste smoke test"
        let bundleID = value(after: "--bundle-id", in: arguments)
        let pid = value(after: "--pid", in: arguments).flatMap { pid_t($0) }

        let outcome = await AutoPasteEngine().paste(
            text: text,
            targetBundleID: bundleID,
            targetPID: pid,
            ownBundleID: Bundle.main.bundleIdentifier
        )

        print("pasted=\(outcome.pasted)")
        print("method=\(outcome.method.rawValue)")
        print("detail=\(outcome.detail)")
        return outcome.pasted ? 0 : 1
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }
        return arguments[valueIndex]
    }
}
