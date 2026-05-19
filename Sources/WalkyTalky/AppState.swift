import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum ProductMode: String, CaseIterable, Identifiable {
        case dictation = "dictation"
        case meeting = "meeting"

        var id: String { rawValue }
    }

    enum MeetingAudioSource: String, CaseIterable, Identifiable {
        case microphone = "microphone"
        case systemAudio = "system audio"

        var id: String { rawValue }
    }

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case dark = "dark"
        case light = "light"

        var id: String { rawValue }
    }

    enum RecordingState: Equatable {
        case idle
        case recording(URL)
        case transcribing(URL)
        case complete
        case failed(String)

        var title: String {
            switch self {
            case .idle:
                "ready"
            case .recording:
                "recording"
            case .transcribing:
                "transcribing"
            case .complete:
                "copied"
            case .failed:
                "needs attention"
            }
        }
    }

    @Published var recordingState: RecordingState = .idle
    @Published var selectedMode: ProductMode = .dictation
    @Published var meetingAudioSource: MeetingAudioSource {
        didSet {
            UserDefaults.standard.set(meetingAudioSource.rawValue, forKey: Self.meetingAudioSourceKey)
        }
    }
    @Published var latestTranscript: TranscriptRecord?
    @Published var recentTranscripts: [TranscriptRecord] = []
    @Published var recentMeetings: [TranscriptRecord] = []
    @Published var activeMeetingSegments: [MeetingSegment] = []
    @Published var availableModels: [String] = []
    @Published var selectedModelName: String = ""
    @Published var shortcutPreset: WalkyShortcutPreset {
        didSet {
            UserDefaults.standard.set(shortcutPreset.rawValue, forKey: Self.shortcutPresetKey)
        }
    }
    @Published var shortcutConfiguration: WalkyShortcutConfiguration {
        didSet {
            shortcutConfiguration.save(defaults: .standard, key: Self.shortcutConfigurationKey)
        }
    }
    @Published var intelligencePreset: WalkyIntelligence.Preset {
        didSet {
            UserDefaults.standard.set(intelligencePreset.rawValue, forKey: Self.intelligencePresetKey)
        }
    }
    @Published var transcriptStyle: TranscriptCleanup.Style {
        didSet {
            UserDefaults.standard.set(transcriptStyle.rawValue, forKey: Self.transcriptStyleKey)
        }
    }
    @Published var autoPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteEnabled, forKey: Self.autoPasteKey)
        }
    }
    @Published var tinydiarizeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(tinydiarizeEnabled, forKey: Self.tinydiarizeKey)
        }
    }
    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey)
        }
    }
    @Published var customDictionary: [CustomDictionaryEntry] {
        didSet {
            Self.saveCustomDictionary(customDictionary)
        }
    }
    @Published var statusDetail = "hold control + option to record."
    @Published var localLLMStatus = LocalLanguageModel.RuntimeStatus.unavailable.title

    let paths: WalkyPaths
    private let recorder: AudioRecorder
    private let systemAudioRecorder = SystemAudioRecorder()
    private let transcriber: WhisperTranscriber
    private var transcriptStore: TranscriptStore?
    private let cleanup = TranscriptCleanup()
    private let autoPasteEngine = AutoPasteEngine()
    private let logger: WalkyLogger
    private var activeMeetingID: UUID?
    private var meetingStartedAt: Date?
    private var meetingChunkStartedAt: Date?
    private var meetingChunkIndex = 0
    private var meetingChunkTimer: Timer?
    private var meetingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var intelligenceWindow: NSWindow?
    private let intelligence = WalkyIntelligence()
    private let localLanguageModel = LocalLanguageModel()
    private var pendingMeetingChunks = 0
    private var meetingIDPendingFinalization: UUID?
    private var pasteTargetBundleIdentifier: String?
    private var pasteTargetProcessIdentifier: pid_t?
    private var lastExternalBundleIdentifier: String?
    private var lastExternalProcessIdentifier: pid_t?
    private let meetingChunkSeconds: TimeInterval = 60
    private static let autoPasteKey = "walkyTalky.autoPasteEnabled"
    private static let intelligencePresetKey = "walkyTalky.intelligencePreset"
    private static let transcriptStyleKey = "walkyTalky.transcriptStyle"
    private static let shortcutPresetKey = "walkyTalky.shortcutPreset"
    private static let shortcutConfigurationKey = "walkyTalky.shortcutConfiguration"
    private static let meetingAudioSourceKey = "walkyTalky.meetingAudioSource"
    private static let tinydiarizeKey = "walkyTalky.tinydiarizeEnabled"
    private static let appearanceModeKey = "walkyTalky.appearanceMode"
    private static let customDictionaryKey = "walkyTalky.customDictionary"
    var shortcutPresetDidChange: (() -> Void)?
    var isActivelyRecording: Bool {
        if case .recording = recordingState {
            return true
        }
        return recorder.isRecording || systemAudioRecorder.isRecording
    }

    var canHandleModifierHoldShortcut: Bool {
        if selectedMode == .meeting, isActivelyRecording {
            return false
        }
        if case .transcribing = recordingState {
            return false
        }
        return true
    }

    init(
        paths: WalkyPaths = .default,
        recorder: AudioRecorder? = nil,
        transcriber: WhisperTranscriber? = nil,
        transcriptStore: TranscriptStore? = nil
    ) {
        self.paths = paths
        self.recorder = recorder ?? AudioRecorder(paths: paths)
        self.transcriber = transcriber ?? WhisperTranscriber(paths: paths)
        self.logger = WalkyLogger(paths: paths)
        self.autoPasteEnabled = true
        UserDefaults.standard.set(true, forKey: Self.autoPasteKey)
        self.tinydiarizeEnabled = UserDefaults.standard.bool(forKey: Self.tinydiarizeKey)
        self.meetingAudioSource = UserDefaults.standard
            .string(forKey: Self.meetingAudioSourceKey)
            .flatMap(MeetingAudioSource.init(rawValue:)) ?? .microphone
        self.shortcutPreset = UserDefaults.standard
            .string(forKey: Self.shortcutPresetKey)
            .flatMap(WalkyShortcutPreset.init(rawValue:)) ?? .controlOption
        self.shortcutConfiguration = WalkyShortcutConfiguration(defaults: .standard, key: Self.shortcutConfigurationKey)
        self.intelligencePreset = UserDefaults.standard
            .string(forKey: Self.intelligencePresetKey)
            .flatMap(WalkyIntelligence.Preset.init(rawValue:)) ?? .paragraphs
        self.transcriptStyle = UserDefaults.standard
            .string(forKey: Self.transcriptStyleKey)
            .flatMap(TranscriptCleanup.Style.init(rawValue:)) ?? .formal
        self.appearanceMode = UserDefaults.standard
            .string(forKey: Self.appearanceModeKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .dark
        self.customDictionary = Self.loadCustomDictionary()

        do {
            try paths.ensureCreated()
            try Self.installBundledRuntimeIfNeeded(paths: paths)
            self.transcriptStore = try transcriptStore ?? TranscriptStore(databaseURL: paths.transcriptsDatabase)
            recoverUnfinishedMeetings()
            recentTranscripts = try self.transcriptStore?.recentDictations() ?? []
            recentMeetings = try self.transcriptStore?.recentMeetings() ?? []
            latestTranscript = recentTranscripts.first
            availableModels = self.transcriber.availableModels()
            selectedModelName = UserDefaults.standard.string(forKey: WhisperTranscriber.preferredModelKey)
                ?? self.transcriber.selectedModelName
            localLLMStatus = localLanguageModel.status().title
            ensureDefaultDictionaryEntries()
            if let app = NSWorkspace.shared.frontmostApplication {
                rememberExternalApp(app)
            }
            observeExternalAppActivations()
        } catch {
            recordingState = .failed("could not prepare local storage.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func toggleRecording() {
        switch recordingState {
        case .idle, .complete, .failed:
            selectedMode == .meeting ? startMeetingRecording() : startRecording()
        case .recording:
            selectedMode == .meeting ? stopMeetingRecording() : stopRecording()
        case .transcribing:
            break
        }
    }

    func toggleDictationRecording() {
        if selectedMode == .meeting, isActivelyRecording {
            return
        }

        selectedMode = .dictation
        switch recordingState {
        case .idle, .complete, .failed:
            startRecording()
        case .recording:
            if recorder.isRecording {
                stopRecording()
            }
        case .transcribing:
            break
        }
    }

    func handleModifierHoldShortcut() {
        if recorder.isRecording, selectedMode == .dictation {
            stopRecording()
            return
        }

        guard !isActivelyRecording else { return }
        startRecording()
    }

    func capturePasteTarget() {
        if let app = NSWorkspace.shared.frontmostApplication, rememberExternalApp(app) {
            pasteTargetBundleIdentifier = app.bundleIdentifier
            pasteTargetProcessIdentifier = app.processIdentifier
            logger.write("paste_target captured pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil")")
            statusDetail = "paste target captured: \(app.localizedName?.lowercased() ?? "current app")."
            return
        }

        if let lastExternalBundleIdentifier, let lastExternalProcessIdentifier {
            pasteTargetBundleIdentifier = lastExternalBundleIdentifier
            pasteTargetProcessIdentifier = lastExternalProcessIdentifier
            logger.write("paste_target fallback_recent pid=\(lastExternalProcessIdentifier) bundle=\(lastExternalBundleIdentifier)")
            statusDetail = "paste target captured from recent app."
        } else {
            logger.write("paste_target missing frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
        }
    }

    func selectDictationMode() {
        if selectedMode == .meeting, isActivelyRecording {
            stopMeetingRecording()
        }
        selectedMode = .dictation
        statusDetail = "dictation mode selected."
    }

    func toggleMeetingModeFromPopover() {
        if selectedMode == .meeting, isActivelyRecording {
            stopMeetingRecording()
            return
        }

        selectedMode = .meeting
        startMeetingRecording()
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        statusDetail = "using \(mode.rawValue.lowercased()) appearance."
    }

    func keepCurrentRecordingLatched() {
        guard isActivelyRecording else {
            toggleDictationRecording()
            return
        }
        statusDetail = "recording latched. press control + option + space again to stop."
    }

    func addDictionaryEntry(spoken: String, replacement: String) {
        let cleanSpoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanSpoken.isEmpty, !cleanReplacement.isEmpty else {
            statusDetail = "add both spoken text and replacement."
            return
        }
        customDictionary.removeAll { $0.spoken == cleanSpoken }
        customDictionary.insert(CustomDictionaryEntry(spoken: cleanSpoken, replacement: cleanReplacement), at: 0)
        statusDetail = "dictionary updated."
    }

    private func ensureDefaultDictionaryEntries() {
        let defaults = [
            CustomDictionaryEntry(spoken: "walkie-talkie", replacement: "walky talky"),
            CustomDictionaryEntry(spoken: "walkie talkie", replacement: "walky talky"),
            CustomDictionaryEntry(spoken: "walky-talky", replacement: "walky talky")
        ]
        var entries = customDictionary
        for item in defaults where !entries.contains(where: { $0.spoken == item.spoken }) {
            entries.append(item)
        }
        if entries != customDictionary {
            customDictionary = entries
        }
    }

    private func learnDictionary(from rawText: String, polishedText: String) {
        let raw = rawText.lowercased()
        let polished = polishedText.lowercased()
        let candidates = [
            ("walkie-talkie", "walky talky"),
            ("walkie talkie", "walky talky"),
            ("walky-talky", "walky talky")
        ]

        for (spoken, replacement) in candidates {
            if raw.contains(spoken) || polished.contains(spoken) {
                if !customDictionary.contains(where: { $0.spoken == spoken }) {
                    customDictionary.insert(CustomDictionaryEntry(spoken: spoken, replacement: replacement), at: 0)
                }
            }
        }
    }

    func deleteDictionaryEntry(_ entry: CustomDictionaryEntry) {
        customDictionary.removeAll { $0.id == entry.id }
        statusDetail = "dictionary entry deleted."
    }

    func analyticsCards() -> [AnalyticsCard] {
        let dictations = recentTranscripts
        let meetings = recentMeetings
        let allRecords = dictations + meetings
        let words = allRecords.reduce(0) { total, record in
            total + record.preview.split { $0.isWhitespace || $0.isNewline }.count
        }
        let meetingMinutes = meetings.reduce(0.0) { $0 + $1.durationSeconds } / 60
        let failedMeetings = meetings.filter { $0.status.lowercased().contains("failed") }.count
        let copiedItems = allRecords.filter { !$0.polishedText.isEmpty || !$0.rawText.isEmpty }.count

        return [
            AnalyticsCard(title: "dictations", value: "\(dictations.count)", detail: "recent saved"),
            AnalyticsCard(title: "meetings", value: "\(meetings.count)", detail: "recent saved"),
            AnalyticsCard(title: "words", value: "\(words)", detail: "recent transcript text"),
            AnalyticsCard(title: "meeting mins", value: String(format: "%.1f", meetingMinutes), detail: "recorded locally"),
            AnalyticsCard(title: "dictionary", value: "\(customDictionary.count)", detail: "custom terms"),
            AnalyticsCard(title: "clean runs", value: "\(max(0, copiedItems - failedMeetings))", detail: "ready transcripts")
        ]
    }

    func startRecording() {
        selectedMode = .dictation
        guard !recorder.isRecording, !systemAudioRecorder.isRecording else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecordingAfterPermission()
        case .notDetermined:
            statusDetail = "microphone access is needed for local recording."
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    granted ? self.startRecordingAfterPermission() : self.failMicrophonePermission()
                }
            }
        case .denied, .restricted:
            failMicrophonePermission()
        @unknown default:
            recordingState = .failed("microphone permission unavailable.")
            statusDetail = "check microphone permission in system settings."
        }
    }

    func stopRecording() {
        guard recorder.isRecording else { return }

        do {
            let url = try recorder.stopRecording()
            recordingState = .transcribing(url)
            statusDetail = "running local transcription."
            Task {
                await transcribe(url)
            }
        } catch {
            recordingState = .failed("could not stop recording.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func startMeetingRecording() {
        selectedMode = .meeting
        guard !recorder.isRecording, !systemAudioRecorder.isRecording else { return }

        if meetingAudioSource == .systemAudio {
            startSystemAudioMeeting()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startMeetingAfterPermission()
        case .notDetermined:
            statusDetail = "microphone access is needed for local meeting recording."
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    granted ? self.startMeetingAfterPermission() : self.failMicrophonePermission()
                }
            }
        case .denied, .restricted:
            failMicrophonePermission()
        @unknown default:
            recordingState = .failed("microphone permission unavailable.")
            statusDetail = "check microphone permission in system settings."
        }
    }

    func stopMeetingRecording() {
        guard selectedMode == .meeting, let meetingID = activeMeetingID else { return }
        meetingChunkTimer?.invalidate()
        meetingChunkTimer = nil

        if systemAudioRecorder.isRecording {
            stopSystemAudioMeeting(meetingID: meetingID)
            return
        }

        guard recorder.isRecording else { return }

        do {
            let chunkURL = try recorder.stopRecording()
            queueMeetingChunk(chunkURL, meetingID: meetingID, segmentIndex: meetingChunkIndex)
            recordingState = .transcribing(chunkURL)
            statusDetail = "finishing local meeting transcript."
            meetingIDPendingFinalization = meetingID
            finalizeMeetingIfReady()
        } catch {
            recordingState = .failed("could not stop meeting.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func copyLatestPolishedTranscript() {
        guard let latestTranscript else { return }
        copy(latestTranscript.polishedText)
        recordingState = .complete
        statusDetail = "copied polished transcript."
    }

    func copyLatestRawTranscript() {
        guard let latestTranscript else { return }
        copy(latestTranscript.rawText)
        recordingState = .complete
        statusDetail = "copied raw transcript."
    }

    func copyTranscript(_ record: TranscriptRecord) {
        copy(record.polishedText.isEmpty ? record.rawText : record.polishedText)
        recordingState = .complete
        statusDetail = "copied transcript."
    }

    func retryMeetingTranscript(_ meeting: TranscriptRecord) {
        statusDetail = "retrying local transcript."
        recordingState = .transcribing(meeting.audioURL)

        Task { @MainActor in
            do {
                let segments = try transcriptStore?.segments(for: meeting.id) ?? []
                var updatedSegments: [MeetingSegment] = []
                for segment in segments {
                    let needsRetry = segment.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if needsRetry, FileManager.default.fileExists(atPath: segment.audioChunkURL.path) {
                        let rawText = try await transcribeMeetingChunk(segment.audioChunkURL)
                        let polishedText = cleanup.polish(rawText, dictionary: customDictionary, style: transcriptStyle)
                        learnDictionary(from: rawText, polishedText: polishedText)
                        let repaired = MeetingSegment(
                            meetingID: segment.meetingID,
                            segmentIndex: segment.segmentIndex,
                            startTime: segment.startTime,
                            endTime: segment.endTime,
                            rawText: rawText,
                            polishedText: polishedText,
                            status: "chunk_complete_retried",
                            audioChunkURL: segment.audioChunkURL
                        )
                        try transcriptStore?.saveSegment(repaired)
                        updatedSegments.append(repaired)
                    } else {
                        updatedSegments.append(segment)
                    }
                }

                let successfulSegments = updatedSegments
                    .sorted { $0.segmentIndex < $1.segmentIndex }
                    .filter { !$0.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let rawText = successfulSegments.map(\.rawText).joined(separator: "\n\n")
                let polishedText = successfulSegments.map { "[\($0.timestampRange)] \($0.polishedText)" }.joined(separator: "\n\n")
                let repairedRecord = TranscriptRecord(
                    id: meeting.id,
                    type: .meeting,
                    createdAt: meeting.createdAt,
                    durationSeconds: meeting.durationSeconds,
                    rawText: rawText,
                    polishedText: polishedText,
                    audioURL: meeting.audioURL,
                    modelUsed: transcriber.selectedModelName,
                    status: successfulSegments.isEmpty ? "transcription_failed" : "complete_retried"
                )
                try transcriptStore?.save(repairedRecord)
                try writeMeetingMarkdown(record: repairedRecord, segments: updatedSegments)
                recentMeetings = try transcriptStore?.recentMeetings() ?? recentMeetings
                latestTranscript = repairedRecord
                recordingState = successfulSegments.isEmpty ? .failed("retry failed.") : .complete
                statusDetail = successfulSegments.isEmpty ? "retry did not produce text." : "retried transcript locally."
            } catch {
                recordingState = .failed("retry failed.")
                statusDetail = error.localizedDescription.lowercased()
            }
        }
    }

    func openIntelligenceForLatestTranscript() {
        guard let latestTranscript else {
            recordingState = .failed("no transcript to analyze.")
            statusDetail = "record dictation or a meeting first."
            return
        }

        openIntelligence(for: latestTranscript)
    }

    func openIntelligenceForLatestMeeting() {
        guard let meeting = recentMeetings.first else {
            recordingState = .failed("no meeting to analyze.")
            statusDetail = "record a meeting first."
            return
        }

        openIntelligence(for: meeting)
    }

    func copyIntelligenceForLatestTranscript() {
        guard let latestTranscript else { return }
        copy(intelligence.analyze(latestTranscript, preset: intelligencePreset).markdown)
        statusDetail = "copied local intelligence."
    }

    func refreshLocalLLMStatus() {
        localLLMStatus = localLanguageModel.status().title
    }

    func copyLocalLLMRefinementForLatestTranscript() {
        guard let latestTranscript else {
            recordingState = .failed("no transcript to refine.")
            statusDetail = "record dictation or a meeting first."
            return
        }

        statusDetail = "running optional local llm polishing."
        Task { @MainActor in
            do {
                let source = latestTranscript.polishedText.isEmpty ? latestTranscript.rawText : latestTranscript.polishedText
                let refined = try await localLanguageModel.refine(source)
                copy(refined)
                recordingState = .complete
                statusDetail = "copied local llm refinement."
            } catch {
                recordingState = .failed("local llm unavailable.")
                statusDetail = error.localizedDescription.lowercased()
                refreshLocalLLMStatus()
            }
        }
    }

    func revealLocalStorage() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.root])
    }

    func revealUpdatePackage() {
        let candidates = [
            FileManager.default.currentDirectoryPath + "/dist/Walky-Talky-mac.dmg",
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Walky-Talky-mac.dmg").path,
            Bundle.main.bundleURL.path
        ].map(URL.init(fileURLWithPath:))

        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusDetail = "opened latest update package."
        } else {
            statusDetail = "update package not found."
        }
    }

    func selectModel(_ modelName: String) {
        selectedModelName = modelName
        UserDefaults.standard.set(modelName, forKey: WhisperTranscriber.preferredModelKey)
        statusDetail = "using \(modelName.lowercased())."
    }

    func refreshModels() {
        availableModels = transcriber.availableModels()
        if selectedModelName.isEmpty {
            selectedModelName = transcriber.selectedModelName
        }
    }

    func selectShortcutPreset(_ preset: WalkyShortcutPreset) {
        shortcutPreset = preset
        shortcutConfiguration = WalkyShortcutConfiguration(
            hold: preset.hold,
            latch: preset.latch,
            meeting: preset.meeting
        )
        shortcutPresetDidChange?()
        statusDetail = "using \(preset.rawValue.lowercased()) shortcuts."
    }

    func updateHoldShortcut(_ binding: WalkyShortcutBinding) {
        shortcutConfiguration.hold = binding
        shortcutPresetDidChange?()
        statusDetail = "hold shortcut set to \(binding.label.lowercased())."
    }

    func updateLatchShortcut(_ binding: WalkyShortcutBinding) {
        shortcutConfiguration.latch = binding
        shortcutPresetDidChange?()
        statusDetail = "latch shortcut set to \(binding.label.lowercased())."
    }

    func updateMeetingShortcut(_ binding: WalkyShortcutBinding) {
        shortcutConfiguration.meeting = binding
        shortcutPresetDidChange?()
        statusDetail = "meeting shortcut set to \(binding.label.lowercased())."
    }

    func resetShortcuts() {
        shortcutConfiguration = .default
        shortcutPreset = .controlOption
        shortcutPresetDidChange?()
        statusDetail = "shortcuts reset."
    }

    func selectTranscriptStyle(_ style: TranscriptCleanup.Style) {
        transcriptStyle = style
        statusDetail = "transcript style set to \(style.rawValue)."
    }

    func selectMeetingAudioSource(_ source: MeetingAudioSource) {
        meetingAudioSource = source
        statusDetail = source == .systemAudio
            ? "system audio meetings use screen recording permission."
            : "meeting mode will record the microphone."
    }

    func installLaunchAtLogin() {
        do {
            let launchAgents = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)

            let bundlePath = Bundle.main.bundleURL.pathExtension == "app"
                ? Bundle.main.bundleURL.path
                : "\(FileManager.default.currentDirectoryPath)/dist/Walky Talky.app"

            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key>
              <string>local.walkytalky.app</string>
              <key>ProgramArguments</key>
              <array>
                <string>/usr/bin/open</string>
                <string>\(bundlePath)</string>
              </array>
              <key>RunAtLoad</key>
              <true/>
            </dict>
            </plist>
            """

            let plistURL = launchAgents.appendingPathComponent("local.walkytalky.app.plist")
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            statusDetail = "launch at login installed."
        } catch {
            recordingState = .failed("launch at login failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func exportLatestMeeting() {
        guard let meeting = recentMeetings.first else {
            recordingState = .failed("no meeting to export.")
            statusDetail = "record a meeting before exporting."
            return
        }

        do {
            let segments = try transcriptStore?.segments(for: meeting.id) ?? []
            let title = "walky-talky-meeting-\(Self.fileTimestamp(meeting.createdAt))"
            let markdownURL = paths.exports.appendingPathComponent("\(title).md")
            let textURL = paths.exports.appendingPathComponent("\(title).txt")
            let body = segments.isEmpty
                ? meeting.polishedText
                : segments.map { "[\($0.timestampRange)] \($0.polishedText)" }.joined(separator: "\n\n")
            let markdown = "# walky talky meeting\n\n- date: \(meeting.createdAt.formatted().lowercased())\n- duration: \(Int(meeting.durationSeconds)) seconds\n- model: \(meeting.modelUsed.lowercased())\n\n\(body.lowercased())\n"
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
            try body.write(to: textURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([markdownURL, textURL])
            statusDetail = "exported meeting transcript."
        } catch {
            recordingState = .failed("export failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func exportLatestMeetingIntelligence() {
        guard let meeting = recentMeetings.first else {
            recordingState = .failed("no meeting to export.")
            statusDetail = "record a meeting before exporting intelligence."
            return
        }

        do {
            let result = intelligence.analyze(meeting, preset: intelligencePreset)
            let title = "walky-talky-intelligence-\(Self.fileTimestamp(meeting.createdAt)).md"
            let url = paths.exports.appendingPathComponent(title)
            try result.markdown.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusDetail = "exported local intelligence."
        } catch {
            recordingState = .failed("export failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func openLatestMeeting() {
        guard let meeting = recentMeetings.first else {
            recordingState = .failed("no meeting to open.")
            statusDetail = "record a meeting before opening a transcript."
            return
        }

        openMeeting(meeting)
    }

    func openMeeting(_ meeting: TranscriptRecord) {
        do {
            let url = try ensureMeetingMarkdown(for: meeting)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusDetail = "opened meeting transcript in finder."
        } catch {
            recordingState = .failed("could not open meeting.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func openSettings() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 530),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "walky talky settings"
        window.contentViewController = NSHostingController(rootView: WalkySettingsView(state: self))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func openIntelligence(for record: TranscriptRecord) {
        let result = intelligence.analyze(record, preset: intelligencePreset)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "walky talky intelligence"
        window.contentViewController = NSHostingController(rootView: WalkyIntelligenceView(result: result))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        intelligenceWindow = window
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func reportShortcutError(_ message: String) {
        recordingState = .failed("shortcut conflict.")
        statusDetail = message.lowercased()
    }

    func deleteLatestMeetingAudio() {
        guard let meeting = recentMeetings.first else {
            recordingState = .failed("no meeting audio to delete.")
            statusDetail = "record a meeting before deleting meeting audio."
            return
        }

        do {
            if FileManager.default.fileExists(atPath: meeting.audioURL.path) {
                try FileManager.default.removeItem(at: meeting.audioURL)
            }
            try transcriptStore?.markMeetingAudioDeleted(for: meeting.id)
            recentMeetings = try transcriptStore?.recentMeetings() ?? recentMeetings
            statusDetail = "deleted latest meeting audio. transcript kept."
        } catch {
            recordingState = .failed("could not delete meeting audio.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func deleteTranscript(_ record: TranscriptRecord) {
        do {
            try transcriptStore?.deleteTranscript(id: record.id)
            recentTranscripts.removeAll { $0.id == record.id }
            if latestTranscript?.id == record.id {
                latestTranscript = recentTranscripts.first
            }
            statusDetail = "deleted dictation."
        } catch {
            recordingState = .failed("could not delete dictation.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func deleteMeeting(_ meeting: TranscriptRecord) {
        do {
            let markdownURL = meetingMarkdownURL(for: meeting)
            if FileManager.default.fileExists(atPath: markdownURL.path) {
                try FileManager.default.removeItem(at: markdownURL)
            }
            if FileManager.default.fileExists(atPath: meeting.audioURL.path) {
                try FileManager.default.removeItem(at: meeting.audioURL)
            }
            try transcriptStore?.deleteMeeting(id: meeting.id)
            recentMeetings.removeAll { $0.id == meeting.id }
            if latestTranscript?.id == meeting.id {
                latestTranscript = recentTranscripts.first
            }
            statusDetail = "deleted meeting."
        } catch {
            recordingState = .failed("could not delete meeting.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    func setAutoPasteEnabled(_ enabled: Bool) {
        autoPasteEnabled = enabled
        if enabled {
            requestAccessibilityIfNeeded()
        }
    }

    func setTinydiarizeEnabled(_ enabled: Bool) {
        tinydiarizeEnabled = enabled
        statusDetail = enabled
            ? "speaker turns require a selected tdrz whisper model."
            : "speaker turns disabled."
    }

    private func startRecordingAfterPermission() {
        guard !recorder.isRecording else { return }

        do {
            let url = try recorder.startDictationRecording()
            recordingState = .recording(url)
            latestTranscript = nil
            statusDetail = "speak now. release the shortcut or press stop when finished."
        } catch {
            recordingState = .failed("recording failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    private func startMeetingAfterPermission() {
        do {
            let meetingID = UUID()
            activeMeetingID = meetingID
            activeMeetingSegments = []
            meetingStartedAt = Date()
            meetingChunkIndex = 0
            pendingMeetingChunks = 0
            meetingIDPendingFinalization = nil
            try startNextMeetingChunk()
            meetingChunkTimer = Timer.scheduledTimer(withTimeInterval: meetingChunkSeconds, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.rollMeetingChunk()
                }
            }
            recordingState = .recording(paths.meetingRecordings.appendingPathComponent(meetingID.uuidString))
            statusDetail = "recording meeting locally in 60-second chunks."
        } catch {
            recordingState = .failed("meeting recording failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    private func startSystemAudioMeeting() {
        Task { @MainActor in
            do {
                let meetingID = UUID()
                activeMeetingID = meetingID
                activeMeetingSegments = []
                meetingStartedAt = Date()
                meetingChunkIndex = 0
                pendingMeetingChunks = 0
                meetingIDPendingFinalization = nil
                try await startNextSystemAudioMeetingChunk()
                meetingChunkTimer = Timer.scheduledTimer(withTimeInterval: meetingChunkSeconds, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        await self?.rollSystemAudioMeetingChunk()
                    }
                }
                recordingState = .recording(paths.meetingRecordings.appendingPathComponent(meetingID.uuidString))
                statusDetail = "recording system audio locally in 60-second chunks."
            } catch {
                recordingState = .failed("system audio unavailable.")
                statusDetail = "allow screen recording for walky talky, then try again. \(error.localizedDescription.lowercased())"
            }
        }
    }

    private func startNextMeetingChunk() throws {
        guard let meetingID = activeMeetingID else { return }
        meetingChunkStartedAt = Date()
        _ = try recorder.startMeetingChunk(meetingID: meetingID, index: meetingChunkIndex)
    }

    private func startNextSystemAudioMeetingChunk() async throws {
        guard let meetingID = activeMeetingID else { return }
        meetingChunkStartedAt = Date()
        let meetingDirectory = paths.meetingRecordings
            .appendingPathComponent(meetingID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: meetingDirectory, withIntermediateDirectories: true)
        let url = meetingDirectory
            .appendingPathComponent(String(format: "system-chunk-%04d.wav", meetingChunkIndex))
        _ = try await systemAudioRecorder.startRecording(to: url)
    }

    private func rollMeetingChunk() {
        guard selectedMode == .meeting, recorder.isRecording, let meetingID = activeMeetingID else { return }

        do {
            let chunkURL = try recorder.stopRecording()
            queueMeetingChunk(chunkURL, meetingID: meetingID, segmentIndex: meetingChunkIndex)
            meetingChunkIndex += 1
            try startNextMeetingChunk()
            statusDetail = "recording meeting locally. \(activeMeetingSegments.count) segments saved."
        } catch {
            recordingState = .failed("meeting chunk failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    private func rollSystemAudioMeetingChunk() async {
        guard selectedMode == .meeting, systemAudioRecorder.isRecording, let meetingID = activeMeetingID else { return }

        do {
            let chunkURL = try await systemAudioRecorder.stopRecording()
            queueMeetingChunk(chunkURL, meetingID: meetingID, segmentIndex: meetingChunkIndex)
            meetingChunkIndex += 1
            try await startNextSystemAudioMeetingChunk()
            statusDetail = "recording system audio locally. \(activeMeetingSegments.count) segments saved."
        } catch {
            recordingState = .failed("system audio chunk failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    private func stopSystemAudioMeeting(meetingID: UUID) {
        Task { @MainActor in
            do {
                let chunkURL = try await systemAudioRecorder.stopRecording()
                queueMeetingChunk(chunkURL, meetingID: meetingID, segmentIndex: meetingChunkIndex)
                recordingState = .transcribing(chunkURL)
                statusDetail = "finishing local system audio transcript."
                meetingIDPendingFinalization = meetingID
                finalizeMeetingIfReady()
            } catch {
                recordingState = .failed("could not stop system audio meeting.")
                statusDetail = error.localizedDescription.lowercased()
            }
        }
    }

    private func queueMeetingChunk(_ chunkURL: URL, meetingID: UUID, segmentIndex: Int) {
        let started = meetingStartedAt ?? Date()
        let chunkStarted = meetingChunkStartedAt ?? started
        let startTime = chunkStarted.timeIntervalSince(started)
        let endTime = Date().timeIntervalSince(started)
        pendingMeetingChunks += 1

        Task { @MainActor in
            defer {
                pendingMeetingChunks = max(0, pendingMeetingChunks - 1)
                finalizeMeetingIfReady()
            }

            do {
                let rawText = try await transcribeMeetingChunk(chunkURL)
                let polishedText = cleanup.polish(rawText, dictionary: customDictionary, style: transcriptStyle)
                learnDictionary(from: rawText, polishedText: polishedText)
                let segment = MeetingSegment(
                    meetingID: meetingID,
                    segmentIndex: segmentIndex,
                    startTime: startTime,
                    endTime: endTime,
                    rawText: rawText,
                    polishedText: polishedText,
                    status: "chunk_complete",
                    audioChunkURL: chunkURL
                )
                try transcriptStore?.saveSegment(segment)
                activeMeetingSegments.append(segment)
                activeMeetingSegments.sort { $0.segmentIndex < $1.segmentIndex }
            } catch {
                let failedSegment = MeetingSegment(
                    meetingID: meetingID,
                    segmentIndex: segmentIndex,
                    startTime: startTime,
                    endTime: endTime,
                    rawText: "",
                    polishedText: "",
                    status: "chunk_failed: \(error.localizedDescription.lowercased())",
                    audioChunkURL: chunkURL
                )
                try? transcriptStore?.saveSegment(failedSegment)
                statusDetail = "a meeting chunk failed. recording can continue."
            }
        }
    }

    private func finalizeMeetingIfReady() {
        guard pendingMeetingChunks == 0, let meetingID = meetingIDPendingFinalization else { return }
        meetingIDPendingFinalization = nil
        finalizeMeeting(meetingID: meetingID)
    }

    private func finalizeMeeting(meetingID: UUID) {
        do {
            let segments = try transcriptStore?.segments(for: meetingID) ?? activeMeetingSegments
            let sortedSegments = segments.sorted { $0.segmentIndex < $1.segmentIndex }
            let successfulSegments = sortedSegments.filter { !$0.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let rawText = successfulSegments.map(\.rawText).joined(separator: "\n\n")
            let polishedText = successfulSegments.map { "[\($0.timestampRange)] \($0.polishedText)" }.joined(separator: "\n\n")
            let createdAt = meetingStartedAt ?? Date()
            let duration = Date().timeIntervalSince(createdAt)
            let record = TranscriptRecord(
                id: meetingID,
                type: .meeting,
                createdAt: createdAt,
                durationSeconds: duration,
                rawText: rawText,
                polishedText: polishedText,
                audioURL: paths.meetingRecordings.appendingPathComponent(meetingID.uuidString, isDirectory: true),
                modelUsed: transcriber.selectedModelName,
                status: successfulSegments.isEmpty ? "transcription_failed" : "complete"
            )
            try transcriptStore?.save(record)
            try writeMeetingMarkdown(record: record, segments: sortedSegments)
            latestTranscript = record
            recentMeetings.insert(record, at: 0)
            recentMeetings = Array(recentMeetings.prefix(8))
            activeMeetingID = nil
            meetingStartedAt = nil
            meetingChunkStartedAt = nil
            pendingMeetingChunks = 0
            recordingState = .complete
            statusDetail = "meeting transcript saved locally."
        } catch {
            recordingState = .failed("meeting finalization failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    private func recoverUnfinishedMeetings() {
        do {
            let ids = try transcriptStore?.recoverableMeetingIDs() ?? []
            for id in ids {
                finalizeRecoveredMeeting(meetingID: id)
            }
            if !ids.isEmpty {
                statusDetail = "recovered \(ids.count) unfinished meeting transcript\(ids.count == 1 ? "" : "s")."
            }
        } catch {
            statusDetail = "meeting recovery needs attention."
        }
    }

    private func finalizeRecoveredMeeting(meetingID: UUID) {
        do {
            let segments = try transcriptStore?.segments(for: meetingID) ?? []
            guard !segments.isEmpty else { return }
            let sortedSegments = segments.sorted { $0.segmentIndex < $1.segmentIndex }
            let successfulSegments = sortedSegments.filter { !$0.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let rawText = successfulSegments.map(\.rawText).joined(separator: "\n\n")
            let polishedText = successfulSegments.map { "[\($0.timestampRange)] \($0.polishedText)" }.joined(separator: "\n\n")
            let duration = sortedSegments.map(\.endTime).max() ?? 0
            let record = TranscriptRecord(
                id: meetingID,
                type: .meeting,
                createdAt: Date(),
                durationSeconds: duration,
                rawText: rawText,
                polishedText: polishedText,
                audioURL: paths.meetingRecordings.appendingPathComponent(meetingID.uuidString, isDirectory: true),
                modelUsed: transcriber.selectedModelName,
                status: successfulSegments.isEmpty ? "recovered_transcription_failed" : "recovered"
            )
            try transcriptStore?.save(record)
            try writeMeetingMarkdown(record: record, segments: sortedSegments)
        } catch {
            statusDetail = "could not recover one meeting."
        }
    }

    private func transcribe(_ audioURL: URL) async {
        do {
            let rawText = try await transcriber.transcribe(audioURL)
            let polishedText = cleanup.polish(rawText, dictionary: customDictionary, style: transcriptStyle)
            learnDictionary(from: rawText, polishedText: polishedText)
            let record = TranscriptRecord(
                id: UUID(),
                createdAt: Date(),
                durationSeconds: recorder.lastRecordingDurationSeconds,
                rawText: rawText,
                polishedText: polishedText,
                audioURL: audioURL,
                modelUsed: transcriber.selectedModelName
            )

            latestTranscript = record
            try transcriptStore?.save(record)
            deleteDictationAudioIfNeeded(for: record)
            recentTranscripts.insert(record, at: 0)
            recentTranscripts = Array(recentTranscripts.prefix(8))
            copy(polishedText)
            pasteIfEnabledAfterCopy()
            recordingState = .complete
        } catch {
            recordingState = .failed("transcription failed.")
            statusDetail = error.localizedDescription.lowercased()
        }
    }

    private func deleteDictationAudioIfNeeded(for record: TranscriptRecord) {
        do {
            if FileManager.default.fileExists(atPath: record.audioURL.path) {
                try FileManager.default.removeItem(at: record.audioURL)
            }
            try transcriptStore?.markAudioDeleted(for: record.id)
        } catch {
            statusDetail = "transcript saved. audio cleanup needs attention."
        }
    }

    private func failMicrophonePermission() {
        recordingState = .failed("microphone access denied.")
        statusDetail = "allow microphone access in system settings to record."
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pasteIfEnabledAfterCopy() {
        guard autoPasteEnabled else { return }

        let targetBundleID = pasteTargetBundleIdentifier
        let targetPID = pasteTargetProcessIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let frontmost = NSWorkspace.shared.frontmostApplication
        logger.write("paste_start enabled=true text_length=\(text.count) target_pid=\(targetPID.map(String.init) ?? "nil") target_bundle=\(targetBundleID ?? "nil") front_pid=\(frontmost.map { String($0.processIdentifier) } ?? "nil") front_bundle=\(frontmost?.bundleIdentifier ?? "nil") ax_trusted=\(AXIsProcessTrusted())")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            let outcome = await autoPasteEngine.paste(
                text: text,
                targetBundleID: targetBundleID,
                targetPID: targetPID,
                ownBundleID: ownBundleID
            )
            logger.write("paste_outcome pasted=\(outcome.pasted) method=\(outcome.method.rawValue) detail=\(outcome.detail)")
            statusDetail = outcome.pasted
                ? "local transcript pasted with \(outcome.method.rawValue)."
                : "copied. \(outcome.detail)"
        }
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func observeExternalAppActivations() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                _ = self?.rememberExternalApp(app)
            }
        }
    }

    @discardableResult
    private func rememberExternalApp(_ app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.activationPolicy == .regular,
              !app.isTerminated else {
            return false
        }

        lastExternalBundleIdentifier = app.bundleIdentifier
        lastExternalProcessIdentifier = app.processIdentifier
        logger.write("external_app active pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil")")
        return true
    }

    private static func loadCustomDictionary() -> [CustomDictionaryEntry] {
        guard let data = UserDefaults.standard.data(forKey: customDictionaryKey),
              let entries = try? JSONDecoder().decode([CustomDictionaryEntry].self, from: data) else {
            return [
                CustomDictionaryEntry(spoken: "walkie-talkie", replacement: "walky talky"),
                CustomDictionaryEntry(spoken: "walkie talkie", replacement: "walky talky"),
                CustomDictionaryEntry(spoken: "walky-talky", replacement: "walky talky")
            ]
        }
        return entries
    }

    private static func saveCustomDictionary(_ entries: [CustomDictionaryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: customDictionaryKey)
    }

    private static func fileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func meetingMarkdownURL(for record: TranscriptRecord) -> URL {
        let title = "walky-talky-meeting-\(Self.fileTimestamp(record.createdAt))-\(record.id.uuidString.prefix(8)).md"
        return paths.meetingTranscripts.appendingPathComponent(title)
    }

    private func ensureMeetingMarkdown(for record: TranscriptRecord) throws -> URL {
        let url = meetingMarkdownURL(for: record)
        if !FileManager.default.fileExists(atPath: url.path) {
            let segments = try transcriptStore?.segments(for: record.id) ?? []
            try writeMeetingMarkdown(record: record, segments: segments)
        }
        return url
    }

    private func transcribeMeetingChunk(_ chunkURL: URL) async throws -> String {
        var lastError: Error?

        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 600_000_000)
            }

            do {
                let text = try await transcriber.transcribe(chunkURL, tinydiarize: tinydiarizeEnabled)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? WalkyError.transcription("local transcription returned no text.")
    }

    private func writeMeetingMarkdown(record: TranscriptRecord, segments: [MeetingSegment]) throws {
        try FileManager.default.createDirectory(at: paths.meetingTranscripts, withIntermediateDirectories: true)
        let sortedSegments = segments.sorted { $0.segmentIndex < $1.segmentIndex }
        let successfulSegments = sortedSegments.filter {
            !$0.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let failedSegments = sortedSegments.filter {
            $0.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let transcriptBody = successfulSegments.isEmpty
            ? record.polishedText
            : successfulSegments
                .map { "[\($0.timestampRange)] \($0.polishedText)" }
                .joined(separator: "\n\n")
        let failureBody = failedSegments.isEmpty
            ? ""
            : "\n\n## needs attention\n\n" + failedSegments
                .map { "- [\($0.timestampRange)] transcription failed. audio chunk: `\($0.audioChunkURL.path)`" }
                .joined(separator: "\n")
        let body = transcriptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "no transcript text was produced. the audio file was saved for retry.\(failureBody)"
            : "\(transcriptBody)\(failureBody)"
        let markdown = """
        # walky talky meeting

        - date: \(record.createdAt.formatted().lowercased())
        - duration: \(Int(record.durationSeconds)) seconds
        - model: \(record.modelUsed.lowercased())
        - status: \(record.status)

        \(body.lowercased())
        """
        try markdown.write(to: meetingMarkdownURL(for: record), atomically: true, encoding: .utf8)
    }

    private static func installBundledRuntimeIfNeeded(paths: WalkyPaths) throws {
        guard let runtimeURL = Bundle.main.resourceURL?.appendingPathComponent("WhisperRuntime") else { return }
        guard FileManager.default.fileExists(atPath: runtimeURL.path) else { return }

        let bundledWhisper = runtimeURL.appendingPathComponent("whisper")
        let targetWhisper = paths.root.appendingPathComponent("whisper")
        if FileManager.default.fileExists(atPath: bundledWhisper.path),
           !FileManager.default.fileExists(atPath: targetWhisper.path) {
            try FileManager.default.copyItem(at: bundledWhisper, to: targetWhisper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetWhisper.path)
        }

        let bundledLib = runtimeURL.appendingPathComponent("lib", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundledLib.path) {
            let targetLib = paths.root.appendingPathComponent("lib", isDirectory: true)
            try FileManager.default.createDirectory(at: targetLib, withIntermediateDirectories: true)
            for file in try FileManager.default.contentsOfDirectory(at: bundledLib, includingPropertiesForKeys: nil) {
                let target = targetLib.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: file, to: target)
                }
            }
        }

        let bundledModels = runtimeURL.appendingPathComponent("models", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundledModels.path) {
            try FileManager.default.createDirectory(at: paths.models, withIntermediateDirectories: true)
            for file in try FileManager.default.contentsOfDirectory(at: bundledModels, includingPropertiesForKeys: nil) {
                let target = paths.models.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: file, to: target)
                }
            }
        }
    }
}
