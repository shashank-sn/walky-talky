import ApplicationServices
import AVFoundation
import SwiftUI

struct WalkyOnboardingView: View {
    @StateObject private var setup = WhisperRuntimeSetup()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    @State private var automationGranted = UserDefaults.standard.bool(forKey: Self.automationGrantedKey)
    @State private var automationDetail = "needed so auto-paste can use system events."
    @State private var lastAutomationProbe = Date.distantPast

    private static let automationGrantedKey = "walkyTalky.automationPermissionChecked"

    let appearanceMode: AppState.AppearanceMode
    let onGetStarted: () -> Void

    private var theme: PopoverTheme {
        appearanceMode == .light ? .light : .dark
    }

    private var permissionsReady: Bool {
        microphoneGranted && accessibilityGranted && screenGranted && automationGranted
    }

    private var isReady: Bool {
        permissionsReady && setup.ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Text("set up permissions once, then keep whisper and models outside the app so walky talky stays small.")
                        .font(.walky(size: 15)).walkyTracking(15)
                        .foregroundStyle(theme.secondary)
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

                        permissionRow(
                            title: "auto paste",
                            subtitle: automationDetail,
                            granted: automationGranted,
                            actionTitle: automationGranted ? "granted" : "allow"
                        ) {
                            requestAutomation()
                        }
                    }

                    runtimeSection
                    modelSection
                }
                .padding(18)
            }

            footerButton
        }
        .frame(width: 420, height: 548)
        .background(theme.background)
        .foregroundStyle(theme.text)
        .walkyDefaultTypography()
        .preferredColorScheme(appearanceMode == .light ? .light : .dark)
        .onAppear {
            refresh(probeAutomation: true)
            setup.refresh()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            refresh()
            setup.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh(probeAutomation: true)
            setup.refresh()
        }
    }

    private var footerButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: onGetStarted) {
                Text(isReady ? "good to start recording" : "finish setup to continue")
                    .font(.walky(size: 15, weight: .semibold)).walkyTracking(15)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isReady ? theme.activeText : theme.secondary)
            .background(isReady ? theme.activePatch : theme.control, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isReady ? theme.activeLine : theme.line, lineWidth: 1)
            }
            .disabled(!isReady)
            .padding(16)
        }
        .background(theme.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: WalkyIconFactory.menuBarIcon())
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(theme.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("walky talky")
                    .font(.walky(size: 24, weight: .semibold)).walkyTracking(24)
                Text("local voice setup")
                    .font(.walky(size: 13, weight: .medium)).walkyTracking(13)
                    .foregroundStyle(theme.secondary)
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.walky(size: 16, weight: .semibold)).walkyTracking(16)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondary)
            .background(theme.control, in: Circle())
            .help("quit walky talky")
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
                    .foregroundStyle(setup.selectedModelInstalled ? theme.activeDot : theme.secondary)
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
                .foregroundStyle(setup.selectedModelInstalled ? theme.activeText : theme.themeSelectedText)
                .background(setup.selectedModelInstalled ? theme.activePatch : theme.themeSelectedBackground, in: RoundedRectangle(cornerRadius: 10))
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
                .foregroundStyle(theme.text)
                .background(theme.control, in: RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(selected ? theme.themeSelectedBackground : theme.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(option.name)
                            .font(.walky(size: 14, weight: .semibold)).walkyTracking(14)
                        if option.id == "large-v3-turbo" {
                            Text("recommended")
                                .font(.walky(size: 10, weight: .bold)).walkyTracking(10)
                                .foregroundStyle(theme.activeText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(theme.activePatch, in: Capsule())
                        }
                    }
                    Text(option.detail)
                        .font(.walky(size: 11)).walkyTracking(11)
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(installed ? "installed" : option.size)
                        .font(.walky(size: 11, weight: .semibold)).walkyTracking(11)
                        .foregroundStyle(installed ? theme.activeDot : theme.secondary)
                    if installed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.walky(size: 14, weight: .semibold)).walkyTracking(14)
                            .foregroundStyle(theme.activeDot)
                    }
                }
            }
            .padding(11)
            .background(modelRowBackground(selected: selected, installed: installed), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? theme.themeSelectedBackground.opacity(0.55) : theme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func modelRowBackground(selected: Bool, installed: Bool) -> Color {
        if selected && installed {
            return theme.activePatch.opacity(0.7)
        }
        if selected {
            return theme.themeSelectedBackground.opacity(0.12)
        }
        return theme.settingBackground
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
                .foregroundStyle(granted ? theme.activeDot : theme.secondary)
                .font(.walky(size: 18, weight: .semibold)).walkyTracking(18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.walky(size: 15, weight: .semibold)).walkyTracking(15)
                Text(subtitle)
                    .font(.walky(size: 12)).walkyTracking(12)
                    .foregroundStyle(theme.secondary)
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
            .foregroundStyle(theme.text)
            .background(theme.control, in: RoundedRectangle(cornerRadius: 8))
            .disabled(granted)
        }
        .padding(13)
        .background(theme.settingBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.line, lineWidth: 1)
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func requestAccessibility() {
        if refreshAccessibility() {
            return
        }

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

    private func requestAutomation() {
        probeAutomationPermission(updateMissingDetail: true)
    }

    @discardableResult
    private func probeAutomationPermission(updateMissingDetail: Bool) -> Bool {
        lastAutomationProbe = Date()
        let source = """
        tell application "System Events"
            get name of first process
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            automationGranted = false
            if updateMissingDetail {
                automationDetail = "could not prepare automation permission request."
            }
            return false
        }

        script.executeAndReturnError(&error)
        if let error {
            automationGranted = false
            UserDefaults.standard.set(false, forKey: Self.automationGrantedKey)
            if updateMissingDetail {
                automationDetail = (error[NSAppleScript.errorMessage] as? String)?.lowercased()
                    ?? "allow walky talky to control system events."
            } else {
                automationDetail = "needed so auto-paste can use system events."
            }
            return false
        }

        automationGranted = true
        automationDetail = "granted for auto-paste through system events."
        UserDefaults.standard.set(true, forKey: Self.automationGrantedKey)
        return true
    }

    private func refresh(probeAutomation: Bool = false) {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        _ = refreshAccessibility()
        screenGranted = CGPreflightScreenCaptureAccess()
        if probeAutomation || (automationGranted == false && Date().timeIntervalSince(lastAutomationProbe) > 3) {
            _ = probeAutomationPermission(updateMissingDetail: false)
        }
    }

    @discardableResult
    private func refreshAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        accessibilityGranted = trusted
        return trusted
    }
}
