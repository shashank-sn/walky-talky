import AppKit
import ApplicationServices
import Carbon

struct WalkyShortcutBinding {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    var isModifierOnly: Bool {
        keyCode == UInt32.max
    }

    static let defaultHold = WalkyShortcutBinding(
        keyCode: UInt32.max,
        modifiers: UInt32(optionKey | controlKey),
        label: "control + option"
    )

    static let defaultLatch = WalkyShortcutBinding(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey | controlKey),
        label: "control + option + space"
    )

    static let defaultMeeting = WalkyShortcutBinding(
        keyCode: UInt32(kVK_ANSI_M),
        modifiers: UInt32(optionKey | controlKey),
        label: "control + option + m"
    )
}

enum WalkyShortcutPreset: String, CaseIterable, Identifiable {
    case controlOption = "control option"

    var id: String { rawValue }

    var hold: WalkyShortcutBinding {
        .defaultHold
    }

    var latch: WalkyShortcutBinding {
        .defaultLatch
    }

    var meeting: WalkyShortcutBinding {
        .defaultMeeting
    }
}

struct WalkyShortcutConfiguration {
    var hold: WalkyShortcutBinding
    var latch: WalkyShortcutBinding
    var meeting: WalkyShortcutBinding

    static let `default` = WalkyShortcutConfiguration(
        hold: .defaultHold,
        latch: .defaultLatch,
        meeting: .defaultMeeting
    )

    init(hold: WalkyShortcutBinding, latch: WalkyShortcutBinding, meeting: WalkyShortcutBinding) {
        self.hold = hold
        self.latch = latch
        self.meeting = meeting
    }

    init(defaults: UserDefaults, key: String) {
        guard let dictionary = defaults.dictionary(forKey: key) as? [String: [String: Any]] else {
            self = .default
            return
        }

        self.init(
            hold: Self.binding(from: dictionary["hold"]) ?? .defaultHold,
            latch: Self.binding(from: dictionary["latch"]) ?? .defaultLatch,
            meeting: Self.binding(from: dictionary["meeting"]) ?? .defaultMeeting
        )
    }

    func save(defaults: UserDefaults, key: String) {
        defaults.set([
            "hold": Self.dictionary(from: hold),
            "latch": Self.dictionary(from: latch),
            "meeting": Self.dictionary(from: meeting)
        ], forKey: key)
    }

    private static func binding(from dictionary: [String: Any]?) -> WalkyShortcutBinding? {
        guard
            let dictionary,
            let keyCode = dictionary["keyCode"] as? UInt32 ?? (dictionary["keyCode"] as? NSNumber)?.uint32Value,
            let modifiers = dictionary["modifiers"] as? UInt32 ?? (dictionary["modifiers"] as? NSNumber)?.uint32Value,
            let label = dictionary["label"] as? String,
            !label.isEmpty
        else {
            return nil
        }

        return WalkyShortcutBinding(keyCode: keyCode, modifiers: modifiers, label: label)
    }

    private static func dictionary(from binding: WalkyShortcutBinding) -> [String: Any] {
        [
            "keyCode": NSNumber(value: binding.keyCode),
            "modifiers": NSNumber(value: binding.modifiers),
            "label": binding.label
        ]
    }
}

@MainActor
final class ShortcutController {
    private var latchHotKeyRef: EventHotKeyRef?
    private var meetingHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localFlagsMonitor: Any?
    private var modifierPollTimer: Timer?
    private var modifierPressedSince: Date?
    private var modifierHoldActive = false
    private var suppressNextModifierRelease = false
    private var suppressHoldUntilModifierRelease = false
    private let holdDelay: TimeInterval = 0.045

    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private let onLatch: () -> Void
    private let onLatchFromHold: () -> Void
    private let onMeeting: () -> Void
    private let onError: (String) -> Void
    private let shouldStartModifierHold: () -> Bool

    init(
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void,
        onLatch: @escaping () -> Void,
        onLatchFromHold: @escaping () -> Void,
        onMeeting: @escaping () -> Void,
        onError: @escaping (String) -> Void,
        shouldStartModifierHold: @escaping () -> Bool
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onLatch = onLatch
        self.onLatchFromHold = onLatchFromHold
        self.onMeeting = onMeeting
        self.onError = onError
        self.shouldStartModifierHold = shouldStartModifierHold
    }

    func registerShortcuts(configuration: WalkyShortcutConfiguration) {
        unregister()
        installCarbonHandler()
        registerModifierHoldShortcut(binding: configuration.hold)
        registerLatchShortcut(binding: configuration.latch)
        registerMeetingShortcut(binding: configuration.meeting)
    }

    func unregister() {
        modifierPollTimer?.invalidate()
        modifierPollTimer = nil
        modifierPressedSince = nil
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        modifierHoldActive = false
        suppressNextModifierRelease = false
        suppressHoldUntilModifierRelease = false

        if let latchHotKeyRef {
            UnregisterEventHotKey(latchHotKeyRef)
            self.latchHotKeyRef = nil
        }
        if let meetingHotKeyRef {
            UnregisterEventHotKey(meetingHotKeyRef)
            self.meetingHotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installCarbonHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let controller = Unmanaged<ShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                Task { @MainActor in
                    if hotKeyID.id == 2 {
                        controller.handleLatchPress()
                    } else if hotKeyID.id == 3 {
                        controller.cancelPendingModifierHoldUntilRelease()
                        controller.onMeeting()
                    }
                }

                return noErr
            },
            1,
            &eventTypes,
            selfPointer,
            &eventHandler
        )

        if status != noErr {
            onError("could not install global shortcut handler.")
        }
    }

    private func registerLatchShortcut(binding: WalkyShortcutBinding) {
        let hotKeyID = EventHotKeyID(signature: Self.signature("wky1"), id: 2)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &latchHotKeyRef
        )
        if status != noErr {
            onError("shortcut conflict for \(binding.label.lowercased()).")
        }
    }

    private func registerMeetingShortcut(binding: WalkyShortcutBinding) {
        let hotKeyID = EventHotKeyID(signature: Self.signature("wky1"), id: 3)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &meetingHotKeyRef
        )
        if status != noErr {
            onError("shortcut conflict for \(binding.label.lowercased()).")
        }
    }

    private func handleLatchPress() {
        cancelPendingModifierHoldUntilRelease()
        if modifierHoldActive {
            modifierHoldActive = false
            suppressNextModifierRelease = true
            onLatchFromHold()
        } else {
            onLatch()
        }
    }

    private var holdBinding: WalkyShortcutBinding = .defaultHold

    private func registerModifierHoldShortcut(binding: WalkyShortcutBinding) {
        holdBinding = binding
        modifierPollTimer = Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollModifierHoldState()
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in
                guard let self else { return }
                self.handleModifierHoldChange(isPressed: self.eventFlagsMatchHold(flags))
            }
            return event
        }
    }

    private func handleModifierHoldChange(isPressed: Bool) {
        if !isPressed {
            modifierPressedSince = nil
            suppressHoldUntilModifierRelease = false
        }

        guard !suppressHoldUntilModifierRelease else {
            return
        }

        if isPressed, !modifierHoldActive, shouldStartModifierHold() {
            modifierHoldActive = true
            onKeyDown()
        } else if !isPressed, modifierHoldActive {
            modifierHoldActive = false
            if suppressNextModifierRelease {
                suppressNextModifierRelease = false
            } else {
                onKeyUp()
            }
        } else if !isPressed {
            suppressNextModifierRelease = false
        }
    }

    private func pollModifierHoldState() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let isPressed = cgFlagsMatchHold(flags)

        if !isPressed {
            handleModifierHoldChange(isPressed: false)
            return
        }

        guard !modifierHoldActive, !suppressHoldUntilModifierRelease, shouldStartModifierHold() else {
            return
        }

        if modifierPressedSince == nil {
            modifierPressedSince = Date()
            return
        }

        if Date().timeIntervalSince(modifierPressedSince ?? Date()) >= holdDelay {
            handleModifierHoldChange(isPressed: true)
        }
    }

    private func cancelPendingModifierHoldUntilRelease() {
        modifierPressedSince = nil
        suppressHoldUntilModifierRelease = true
    }

    private static func signature(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }

    private func eventFlagsMatchHold(_ flags: NSEvent.ModifierFlags) -> Bool {
        let required = holdBinding.modifiers
        if required & UInt32(controlKey) != 0, !flags.contains(.control) { return false }
        if required & UInt32(optionKey) != 0, !flags.contains(.option) { return false }
        if required & UInt32(shiftKey) != 0, !flags.contains(.shift) { return false }
        if required & UInt32(cmdKey) != 0, !flags.contains(.command) { return false }
        return required != 0
    }

    private func cgFlagsMatchHold(_ flags: CGEventFlags) -> Bool {
        let required = holdBinding.modifiers
        if required & UInt32(controlKey) != 0, !flags.contains(.maskControl) { return false }
        if required & UInt32(optionKey) != 0, !flags.contains(.maskAlternate) { return false }
        if required & UInt32(shiftKey) != 0, !flags.contains(.maskShift) { return false }
        if required & UInt32(cmdKey) != 0, !flags.contains(.maskCommand) { return false }
        return required != 0
    }
}
