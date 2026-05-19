import AppKit
import Carbon
import SwiftUI

struct WalkySettingsView: View {
    @ObservedObject var state: AppState
    @State private var editingShortcut: ShortcutEditTarget?

    var body: some View {
        ZStack {
            settingsContent

            if let editingShortcut {
                ShortcutCaptureOverlay(
                    target: editingShortcut,
                    onCancel: { self.editingShortcut = nil },
                    onCapture: { binding in
                        apply(binding, to: editingShortcut)
                        self.editingShortcut = nil
                    }
                )
            }
        }
        .frame(width: 500, height: 560)
        .walkyDefaultTypography()
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: WalkyIconFactory.popoverIcon())
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("walky talky")
                        .font(.walky(.headline)).tracking(0.17)
                    Text("local-first voice utility")
                        .font(.walky(.caption)).tracking(0.12)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Picker("transcription model", selection: Binding(
                get: { state.selectedModelName },
                set: { state.selectModel($0) }
            )) {
                if state.availableModels.isEmpty {
                    Text("no local models found").tag("")
                } else {
                    ForEach(state.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            HStack {
                Button("refresh models") {
                    state.refreshModels()
                }
                Button("reveal local files") {
                    state.revealLocalStorage()
                }
                Button("launch at login") {
                    state.installLaunchAtLogin()
                }
            }

            Toggle("auto-paste after dictation", isOn: Binding(
                get: { state.autoPasteEnabled },
                set: { state.setAutoPasteEnabled($0) }
            ))

            Toggle("speaker turns with tdrz model", isOn: Binding(
                get: { state.tinydiarizeEnabled },
                set: { state.setTinydiarizeEnabled($0) }
            ))

            Picker("shortcut preset", selection: Binding(
                get: { state.shortcutPreset },
                set: { state.selectShortcutPreset($0) }
            )) {
                ForEach(WalkyShortcutPreset.allCases) { preset in
                    Text(preset.rawValue.lowercased()).tag(preset)
                }
            }

            Picker("meeting audio", selection: Binding(
                get: { state.meetingAudioSource },
                set: { state.selectMeetingAudioSource($0) }
            )) {
                ForEach(AppState.MeetingAudioSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }

            Picker("cleanup preset", selection: $state.intelligencePreset) {
                ForEach(WalkyIntelligence.Preset.allCases) { preset in
                    Text(preset.rawValue.lowercased()).tag(preset)
                }
            }

            HStack {
                Button("analyze latest") {
                    state.openIntelligenceForLatestTranscript()
                }
                Button("copy analysis") {
                    state.copyIntelligenceForLatestTranscript()
                }
                Button("local llm copy") {
                    state.copyLocalLLMRefinementForLatestTranscript()
                }
                Button("export meeting analysis") {
                    state.exportLatestMeetingIntelligence()
                }
            }

            HStack {
                Text(state.localLLMStatus.lowercased())
                    .font(.walky(.caption)).tracking(0.12)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("refresh llm") {
                    state.refreshLocalLLMStatus()
                }
                .font(.walky(.caption)).tracking(0.12)
            }

            Divider()

            shortcutSection

            Spacer()
        }
        .padding(20)
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("shortcuts")
                    .font(.walky(.subheadline, weight: .semibold)).tracking(0.15)
                Spacer()
                Button("reset") {
                    state.resetShortcuts()
                }
                .font(.walky(.caption, weight: .semibold)).tracking(0.12)
            }

            Text("double click a shortcut to edit it.")
                .font(.walky(.caption)).tracking(0.12)
                .foregroundStyle(.secondary)

            shortcutRow(
                title: "hold to record",
                binding: state.shortcutConfiguration.hold,
                target: .hold
            )
            shortcutRow(
                title: "latch start or stop",
                binding: state.shortcutConfiguration.latch,
                target: .latch
            )
            shortcutRow(
                title: "meeting start or stop",
                binding: state.shortcutConfiguration.meeting,
                target: .meeting
            )
        }
    }

    private func shortcutRow(title: String, binding: WalkyShortcutBinding, target: ShortcutEditTarget) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.walky(.caption, weight: .semibold)).tracking(0.12)
            Spacer()
            Text(binding.label.lowercased())
                .font(.walky(.caption, weight: .semibold)).tracking(0.12)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.gray.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingShortcut = target
        }
    }

    private func apply(_ binding: WalkyShortcutBinding, to target: ShortcutEditTarget) {
        switch target {
        case .hold:
            state.updateHoldShortcut(binding)
        case .latch:
            state.updateLatchShortcut(binding)
        case .meeting:
            state.updateMeetingShortcut(binding)
        }
    }
}

enum ShortcutEditTarget {
    case hold
    case latch
    case meeting

    var title: String {
        switch self {
        case .hold:
            "hold to record"
        case .latch:
            "latch start or stop"
        case .meeting:
            "meeting start or stop"
        }
    }

    var acceptsModifierOnly: Bool {
        self == .hold
    }
}

struct ShortcutCaptureOverlay: View {
    let target: ShortcutEditTarget
    let onCancel: () -> Void
    let onCapture: (WalkyShortcutBinding) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("edit \(target.title)")
                    .font(.walky(.headline)).tracking(0.17)
                Text(target.acceptsModifierOnly ? "press the new modifier combo." : "press the new key combo.")
                    .font(.walky(.caption)).tracking(0.12)
                    .foregroundStyle(.secondary)

                ShortcutCaptureView(
                    acceptsModifierOnly: target.acceptsModifierOnly,
                    onCancel: onCancel,
                    onCapture: onCapture
                )
                .frame(height: 64)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                }

                Button("cancel", action: onCancel)
                    .font(.walky(.caption, weight: .semibold)).tracking(0.12)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 24)
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let acceptsModifierOnly: Bool
    let onCancel: () -> Void
    let onCapture: (WalkyShortcutBinding) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.acceptsModifierOnly = acceptsModifierOnly
        view.onCancel = onCancel
        view.onCapture = onCapture
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.acceptsModifierOnly = acceptsModifierOnly
        nsView.onCancel = onCancel
        nsView.onCapture = onCapture
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var acceptsModifierOnly = false
    var onCancel: (() -> Void)?
    var onCapture: ((WalkyShortcutBinding) -> Void)?
    private var pendingModifierCapture: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text = "listening"
        let fontDescriptor = NSFont.systemFont(ofSize: 13, weight: .semibold)
            .fontDescriptor
            .withDesign(.rounded) ?? NSFont.systemFont(ofSize: 13, weight: .semibold).fontDescriptor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(descriptor: fontDescriptor, size: 13) ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
            .kern: 0.13,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    override func keyDown(with event: NSEvent) {
        pendingModifierCapture?.cancel()
        pendingModifierCapture = nil

        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        let modifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return }

        let keyCode = UInt32(event.keyCode)
        let label = ShortcutFormatter.label(keyCode: keyCode, modifiers: modifiers)
        onCapture?(WalkyShortcutBinding(keyCode: keyCode, modifiers: modifiers, label: label))
    }

    override func flagsChanged(with event: NSEvent) {
        guard acceptsModifierOnly else { return }

        let modifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return }

        pendingModifierCapture?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let label = ShortcutFormatter.label(keyCode: UInt32.max, modifiers: modifiers)
            self.onCapture?(WalkyShortcutBinding(keyCode: UInt32.max, modifiers: modifiers, label: label))
        }
        pendingModifierCapture = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }
}

enum ShortcutFormatter {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    static func label(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("command") }
        if keyCode != UInt32.max {
            parts.append(keyLabel(keyCode))
        }
        return parts.joined(separator: " + ")
    }

    private static func keyLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "space"
        case kVK_Return:
            return "return"
        case kVK_Tab:
            return "tab"
        case kVK_Delete:
            return "delete"
        case kVK_Escape:
            return "escape"
        case kVK_ANSI_A...kVK_ANSI_Z:
            return ansiLetterLabel(keyCode)
        case kVK_ANSI_0:
            return "0"
        case kVK_ANSI_1:
            return "1"
        case kVK_ANSI_2:
            return "2"
        case kVK_ANSI_3:
            return "3"
        case kVK_ANSI_4:
            return "4"
        case kVK_ANSI_5:
            return "5"
        case kVK_ANSI_6:
            return "6"
        case kVK_ANSI_7:
            return "7"
        case kVK_ANSI_8:
            return "8"
        case kVK_ANSI_9:
            return "9"
        default:
            return "key \(keyCode)"
        }
    }

    private static func ansiLetterLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        default: return "key \(keyCode)"
        }
    }
}
