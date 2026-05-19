import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private let paths: WalkyPaths
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    private(set) var lastRecordingDurationSeconds: TimeInterval = 0

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    init(paths: WalkyPaths) {
        self.paths = paths
    }

    func startDictationRecording() throws -> URL {
        try paths.ensureCreated()

        let url = paths.dictationRecordings
            .appendingPathComponent("dictation-\(Self.timestamp()).wav")
        return try startRecording(to: url)
    }

    func startMeetingChunk(meetingID: UUID, index: Int) throws -> URL {
        try paths.ensureCreated()

        let meetingDirectory = paths.meetingRecordings
            .appendingPathComponent(meetingID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: meetingDirectory, withIntermediateDirectories: true)

        let url = meetingDirectory
            .appendingPathComponent(String(format: "chunk-%04d.wav", index))
        return try startRecording(to: url)
    }

    private func startRecording(to url: URL) throws -> URL {
        if isRecording {
            _ = try stopRecording()
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let sessionRecorder = try AVAudioRecorder(url: url, settings: settings)
        sessionRecorder.delegate = self
        sessionRecorder.prepareToRecord()

        guard sessionRecorder.record() else {
            throw WalkyError.recording("the microphone did not start recording.")
        }

        startedAt = Date()
        recorder = sessionRecorder
        return url
    }

    func stopRecording() throws -> URL {
        guard let recorder else {
            throw WalkyError.recording("no active recording exists.")
        }

        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        if let startedAt {
            lastRecordingDurationSeconds = Date().timeIntervalSince(startedAt)
        }
        self.startedAt = nil
        return url
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
