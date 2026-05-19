import AVFoundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private final class SendableWriter: @unchecked Sendable {
        let value: AVAssetWriter

        init(_ value: AVAssetWriter) {
            self.value = value
        }
    }

    private let queue = DispatchQueue(label: "local.walkytalky.system-audio")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startedWriting = false
    private var outputURL: URL?

    private(set) var isRecording = false

    func startRecording(to url: URL) async throws -> URL {
        if isRecording {
            _ = try await stopRecording()
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw WalkyError.recording("no display is available for system audio capture.")
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .wav)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw WalkyError.recording("system audio writer could not be prepared.")
        }
        writer.add(input)

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)

        self.writer = writer
        self.input = input
        self.stream = stream
        self.outputURL = url
        self.startedWriting = false

        try await stream.startCapture()
        isRecording = true
        return url
    }

    func stopRecording() async throws -> URL {
        guard let stream, let writer, let input, let outputURL else {
            throw WalkyError.recording("no active system audio recording exists.")
        }

        try await stream.stopCapture()
        self.stream = nil
        isRecording = false

        input.markAsFinished()

        let writerBox = SendableWriter(writer)
        return try await withCheckedThrowingContinuation { continuation in
            writerBox.value.finishWriting {
                self.writer = nil
                self.input = nil
                self.outputURL = nil
                self.startedWriting = false

                if writerBox.value.status == .completed {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(
                        throwing: WalkyError.recording(
                            writerBox.value.error?.localizedDescription.lowercased() ?? "system audio recording could not be finalized."
                        )
                    )
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer), let writer, let input else {
            return
        }

        if !startedWriting {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: timestamp)
            startedWriting = true
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
