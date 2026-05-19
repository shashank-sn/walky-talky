import ApplicationServices
import AVFoundation
import SwiftUI

struct WalkyOnboardingView: View {
    @StateObject private var setup = WhisperRuntimeSetup()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenGranted = CGPreflightScreenCaptureAccess()

    let onGetStarted: () -> Void

    private var permissionsReady: Bool {
        microphoneGranted && accessibilityGranted && screenGranted
    }

    private var isReady: Bool {
        permissionsReady && setup.ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Text("set up permissions once, then keep whisper and models outside the app so walky talky stays small.")
                .font(.walky(size: 15)).walkyTracking(15)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                permissionRow(
                    title: "microphone",
                    subtitle: "needed for dictation and microphone meetings.",
                    granted: microphoneGranted,
                    actionTitle: microphoneGranted ? "granted" : "grant"
                ) {
                    requestMicrophone()
                }

                permissionRow(
                    title: "accessibility",
                    subtitle: "needed for hold-to-talk shortcuts and auto paste.",
                    granted: accessibilityGranted,
                    actionTitle: accessibilityGranted ? "granted" : "open settings"
                ) {
                    requestAccessibility()
                }

                permissionRow(
                    title: "screen recording",
                    subtitle: "needed when meeting mode records system audio.",
                    granted: screenGranted,
                    actionTitle: screenGranted ? "granted" : "grant"
                ) {
                    requestScreenRecording()
                }
            }

            runtimeSection
            modelSection

            Button(action: onGetStarted) {
                Text(isReady ? "good to start recording" : "finish setup to continue")
                    .font(.walky(size: 15, weight: .semibold)).walkyTracking(15)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isReady ? Color(red: 0.04, green: 0.13, blue: 0.05) : .secondary)
            .background(isReady ? Color(red: 0.875, green: 0.973, blue: 0.875) : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isReady ? Color(red: 0.37, green: 0.67, blue: 0.39) : Color.gray.opacity(0.2), lineWidth: 1)
            }
            .disabled(!isReady)
        }
        .padding(24)
        .frame(width: 540, height: 660)
        .walkyDefaultTypography()
        .onAppear {
            refresh()
            setup.refresh()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refresh()
            setup.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: WalkyIconFactory.popoverIcon())
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("walky talky")
                    .font(.walky(size: 24, weight: .semibold)).walkyTracking(24)
                Text("local voice setup")
                    .font(.walky(size: 13, weight: .medium)).walkyTracking(13)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("local whisper")
                .font(.walky(size: 14, weight: .bold)).walkyTracking(14)

            permissionRow(
                title: setup.runtimeInstalled ? "runtime installed" : "runtime missing",
                subtitle: setup.runtimeInstalled
                    ? setup.runtimeDetail
                    : "place whisper in application support, or add whisper-cli to path.",
                granted: setup.runtimeInstalled,
                actionTitle: setup.runtimeInstalled ? "installed" : "open folder"
            ) {
                setup.openRuntimeFolder()
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("model")
                    .font(.walky(size: 14, weight: .bold)).walkyTracking(14)
                Spacer()
                Text(setup.status)
                    .font(.walky(size: 12, weight: .semibold)).walkyTracking(12)
                    .foregroundStyle(setup.selectedModelInstalled ? Color(red: 0.2, green: 0.62, blue: 0.25) : .secondary)
                    .lineLimit(1)
            }

            VStack(spacing: 8) {
                ForEach(WhisperRuntimeSetup.modelOptions) { option in
                    modelRow(option)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await setup.installSelectedModel() }
                } label: {
                    Text(modelActionTitle)
                        .font(.walky(size: 13, weight: .semibold)).walkyTracking(13)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(setup.selectedModelInstalled ? Color(red: 0.04, green: 0.13, blue: 0.05) : .white)
                .background(setup.selectedModelInstalled ? Color(red: 0.875, green: 0.973, blue: 0.875) : Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                .disabled(setup.isWorking)

                Button {
                    setup.openModelsFolder()
                } label: {
                    Text("open folder")
                        .font(.walky(size: 13, weight: .semibold)).walkyTracking(13)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var modelActionTitle: String {
        if setup.isWorking {
            return "downloading"
        }
        if setup.selectedModelInstalled {
            return "installed"
        }
        return "download selected model"
    }

    private func modelRow(_ option: WhisperModelOption) -> some View {
        let selected = setup.selectedModelID == option.id
        let installed = setup.installedModelNames.contains(option.fileName)

        return Button {
            setup.choose(option)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.walky(size: 16, weight: .semibold)).walkyTracking(16)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(option.name)
                            .font(.walky(size: 14, weight: .semibold)).walkyTracking(14)
                        if option.id == "large-v3-turbo" {
                            Text("recommended")
                                .font(.walky(size: 10, weight: .bold)).walkyTracking(10)
                                .foregroundStyle(Color(red: 0.08, green: 0.35, blue: 0.12))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.875, green: 0.973, blue: 0.875), in: Capsule())
                        }
                    }
                    Text(option.detail)
                        .font(.walky(size: 11)).walkyTracking(11)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(installed ? "installed" : option.size)
                        .font(.walky(size: 11, weight: .semibold)).walkyTracking(11)
                        .foregroundStyle(installed ? Color(red: 0.2, green: 0.62, blue: 0.25) : .secondary)
                    if installed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.walky(size: 14, weight: .semibold)).walkyTracking(14)
                            .foregroundStyle(Color(red: 0.2, green: 0.62, blue: 0.25))
                    }
                }
            }
            .padding(11)
            .background(modelRowBackground(selected: selected, installed: installed), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor.opacity(0.55) : Color.gray.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func modelRowBackground(selected: Bool, installed: Bool) -> Color {
        if selected && installed {
            return Color(red: 0.875, green: 0.973, blue: 0.875).opacity(0.7)
        }
        if selected {
            return Color.accentColor.opacity(0.12)
        }
        return Color.gray.opacity(0.06)
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color(red: 0.12, green: 0.62, blue: 0.22) : .secondary)
                .font(.walky(size: 18, weight: .semibold)).walkyTracking(18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.walky(size: 15, weight: .semibold)).walkyTracking(15)
                Text(subtitle)
                    .font(.walky(size: 12)).walkyTracking(12)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: action) {
                Text(actionTitle)
                    .font(.walky(size: 12, weight: .semibold)).walkyTracking(12)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .disabled(granted)
        }
        .padding(13)
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        refresh()
    }

    private func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        refresh()
    }

    private func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        screenGranted = CGPreflightScreenCaptureAccess()
    }
}
