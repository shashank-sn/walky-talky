import AppKit
import SwiftUI

@MainActor
final class WalkyAppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var shortcutController: ShortcutController?
    private var outsideClickMonitor: Any?
    private var showingOnboarding = false
    private static let onboardingCompleteKey = "walkyTalky.onboardingComplete"
    private static let onboardingVersionKey = "walkyTalky.onboardingVersion"
    private static let requiredOnboardingVersion = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.shortcutPresetDidChange = { [weak self] in
            self?.configureShortcut()
        }

        startMenuBarMode(showingOnboarding: !Self.hasCompletedCurrentOnboarding)
        if showingOnboarding {
            showPopover()
        }
    }

    private func startMenuBarMode(showingOnboarding: Bool = false) {
        self.showingOnboarding = showingOnboarding
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover(showingOnboarding: showingOnboarding)
        if !showingOnboarding {
            configureShortcut()
        }
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

    private func configurePopover(showingOnboarding: Bool) {
        let popover = self.popover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 548)
        if showingOnboarding {
            popover.contentViewController = NSHostingController(
                rootView: WalkyOnboardingView(appearanceMode: state.appearanceMode) { [weak self] in
                    self?.finishOnboarding()
                }
            )
        } else {
            popover.contentViewController = NSHostingController(rootView: WalkyPopoverView(state: state))
        }
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

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        UserDefaults.standard.set(Self.requiredOnboardingVersion, forKey: Self.onboardingVersionKey)
        showingOnboarding = false
        popover?.performClose(nil)
        stopOutsideClickMonitor()
        configurePopover(showingOnboarding: false)
        configureShortcut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.showPopover()
        }
    }

    private static var hasCompletedCurrentOnboarding: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompleteKey)
            && UserDefaults.standard.integer(forKey: onboardingVersionKey) >= requiredOnboardingVersion
    }

    @objc private func togglePopover() {
        guard let popover, statusItem?.button != nil else { return }

        if popover.isShown {
            popover.performClose(nil)
            stopOutsideClickMonitor()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        startOutsideClickMonitor()
        NSApp.activate(ignoringOtherApps: true)
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
