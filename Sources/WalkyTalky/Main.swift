import AppKit

@main
enum WalkyTalkyMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--accessibility-status") {
            exit(AutoPasteSmokeTest.accessibilityStatus())
        }

        if CommandLine.arguments.contains("--autopaste-smoke-test") {
            let exitCode = runSmokeTest()
            exit(exitCode)
        }

        let app = NSApplication.shared
        let delegate = WalkyAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    @MainActor
    private static func runSmokeTest() -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Int32 = 1
        Task { @MainActor in
            result = await AutoPasteSmokeTest.run(arguments: CommandLine.arguments)
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return result
    }
}
