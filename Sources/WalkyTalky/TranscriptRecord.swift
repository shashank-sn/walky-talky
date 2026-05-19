import Foundation

struct TranscriptRecord: Identifiable, Equatable {
    enum TranscriptType: String {
        case dictation
        case meeting
    }

    let id: UUID
    let type: TranscriptType
    let createdAt: Date
    let durationSeconds: TimeInterval
    let rawText: String
    let polishedText: String
    let audioURL: URL
    let modelUsed: String
    let status: String

    init(
        id: UUID,
        type: TranscriptType = .dictation,
        createdAt: Date,
        durationSeconds: TimeInterval,
        rawText: String,
        polishedText: String,
        audioURL: URL,
        modelUsed: String,
        status: String = "complete"
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.rawText = rawText
        self.polishedText = polishedText
        self.audioURL = audioURL
        self.modelUsed = modelUsed
        self.status = status
    }

    var preview: String {
        polishedText.isEmpty ? rawText : polishedText
    }

    var timestamp: String {
        createdAt.formatted(date: .omitted, time: .shortened)
    }
}

struct MeetingSegment: Identifiable, Equatable {
    var id: String { "\(meetingID.uuidString)-\(segmentIndex)" }

    let meetingID: UUID
    let segmentIndex: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let rawText: String
    let polishedText: String
    let status: String
    let audioChunkURL: URL

    var timestampRange: String {
        "\(Self.format(startTime))-\(Self.format(endTime))"
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
