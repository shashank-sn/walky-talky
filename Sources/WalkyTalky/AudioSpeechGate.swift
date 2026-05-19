import AVFoundation
import Foundation

struct AudioSpeechGateDecision: Equatable {
    let shouldSkip: Bool
    let reason: String
    let peakRMS: Float
    let peakAmplitude: Float
    let windows: Int
    let speechWindows: Int
}

struct AudioSpeechGate {
    private let silenceRMSThreshold: Float = 0.002
    private let speechRMSThreshold: Float = 0.003
    private let speechPeakThreshold: Float = 0.02
    private let strongSpeechRMSThreshold: Float = 0.006
    private let windowFrameCount: AVAudioFrameCount = 1600

    func evaluate(_ audioURL: URL) -> AudioSpeechGateDecision {
        guard
            let file = try? AVAudioFile(forReading: audioURL),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: min(windowFrameCount, AVAudioFrameCount(file.length))
            ),
            file.length > 0
        else {
            return AudioSpeechGateDecision(
                shouldSkip: false,
                reason: "unavailable",
                peakRMS: 0,
                peakAmplitude: 0,
                windows: 0,
                speechWindows: 0
            )
        }

        var peakRMS: Float = 0
        var peakAmplitude: Float = 0
        var windows = 0
        var speechWindows = 0

        while file.framePosition < file.length {
            do {
                try file.read(into: buffer, frameCount: windowFrameCount)
            } catch {
                break
            }

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }
            windows += 1

            let metrics = metrics(for: buffer, frameLength: frameLength)
            peakRMS = max(peakRMS, metrics.rms)
            peakAmplitude = max(peakAmplitude, metrics.peak)

            if metrics.rms >= speechRMSThreshold, metrics.peak >= speechPeakThreshold {
                speechWindows += 1
            }
        }

        let reason: String
        let shouldSkip: Bool
        if windows == 0 {
            reason = "unavailable"
            shouldSkip = false
        } else if peakRMS < silenceRMSThreshold {
            reason = "silence"
            shouldSkip = true
        } else if speechWindows == 0, peakRMS < strongSpeechRMSThreshold {
            reason = "insufficient speech"
            shouldSkip = true
        } else {
            reason = "speech detected"
            shouldSkip = false
        }

        return AudioSpeechGateDecision(
            shouldSkip: shouldSkip,
            reason: reason,
            peakRMS: peakRMS,
            peakAmplitude: peakAmplitude,
            windows: windows,
            speechWindows: speechWindows
        )
    }

    private func metrics(for buffer: AVAudioPCMBuffer, frameLength: Int) -> (rms: Float, peak: Float) {
        if let channels = buffer.floatChannelData {
            return floatMetrics(channels: channels, channelCount: Int(buffer.format.channelCount), frameLength: frameLength)
        }

        if let channels = buffer.int16ChannelData {
            return int16Metrics(channels: channels, channelCount: Int(buffer.format.channelCount), frameLength: frameLength)
        }

        return (0, 0)
    }

    private func floatMetrics(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameLength: Int
    ) -> (rms: Float, peak: Float) {
        var sumSquares: Float = 0
        var peak: Float = 0
        let sampleCount = max(1, channelCount * frameLength)

        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frame in 0..<frameLength {
                let value = channel[frame]
                sumSquares += value * value
                peak = max(peak, abs(value))
            }
        }

        return (sqrt(sumSquares / Float(sampleCount)), peak)
    }

    private func int16Metrics(
        channels: UnsafePointer<UnsafeMutablePointer<Int16>>,
        channelCount: Int,
        frameLength: Int
    ) -> (rms: Float, peak: Float) {
        var sumSquares: Float = 0
        var peak: Float = 0
        let sampleCount = max(1, channelCount * frameLength)

        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frame in 0..<frameLength {
                let value = Float(channel[frame]) / Float(Int16.max)
                sumSquares += value * value
                peak = max(peak, abs(value))
            }
        }

        return (sqrt(sumSquares / Float(sampleCount)), peak)
    }
}
