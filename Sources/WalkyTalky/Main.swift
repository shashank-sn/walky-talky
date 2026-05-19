import AppKit

@main
enum WalkyTalkyMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = WalkyAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
