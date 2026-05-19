import AppKit
import SwiftUI

@MainActor
final class WalkyAppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var shortcutController: ShortcutController?
    private var onboardingWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private static let onboardingCompleteKey = "walkyTalky.onboardingComplete"
    private static let onboardingVersionKey = "walkyTalky.onboardingVersion"
    private static let requiredOnboardingVersion = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.shortcutPresetDidChange = { [weak self] in
            self?.configureShortcut()
        }

        if Self.hasCompletedCurrentOnboarding {
            startMenuBarMode()
        } else {
            showOnboarding()
        }
    }

    private func startMenuBarMode() {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureShortcut()
    }

    private func configureStatusItem() {
        if statusItem != nil { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = WalkyIconFactory.menuBarIcon()
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown
        item.length = 22
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
    }

    private func configurePopover() {
        if popover != nil { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 548)
        popover.contentViewController = NSHostingController(rootView: WalkyPopoverView(state: state))
        self.popover = popover
    }

    private func configureShortcut() {
        shortcutController?.unregister()
        let controller = ShortcutController(
            onKeyDown: { [weak self] in
                self?.state.capturePasteTarget()
                self?.state.handleModifierHoldShortcut()
            },
            onKeyUp: { [weak self] in
                self?.state.stopRecording()
            },
            onLatch: { [weak self] in
                self?.state.capturePasteTarget()
                self?.state.toggleDictationRecording()
            },
            onLatchFromHold: { [weak self] in
                self?.state.keepCurrentRecordingLatched()
            },
            onMeeting: { [weak self] in
                self?.state.selectedMode = .meeting
                self?.state.toggleRecording()
            },
            onError: { [weak self] message in
                self?.state.reportShortcutError(message)
            },
            shouldStartModifierHold: { [weak self] in
                self?.state.canHandleModifierHoldShortcut == true
            }
        )
        controller.registerShortcuts(configuration: state.shortcutConfiguration)
        shortcutController = controller
    }

    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "walky talky setup"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: WalkyOnboardingView { [weak self] in
                self?.finishOnboarding()
            }
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        UserDefaults.standard.set(Self.requiredOnboardingVersion, forKey: Self.onboardingVersionKey)
        onboardingWindow?.close()
        onboardingWindow = nil
        startMenuBarMode()
    }

    private static var hasCompletedCurrentOnboarding: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompleteKey)
            && UserDefaults.standard.integer(forKey: onboardingVersionKey) >= requiredOnboardingVersion
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            stopOutsideClickMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startOutsideClickMonitor()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.popover?.performClose(nil)
                self?.stopOutsideClickMonitor()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

}
