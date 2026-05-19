import Foundation
import SQLite3

final class TranscriptStore {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func recentDictations(limit: Int = 8) throws -> [TranscriptRecord] {
        try recentTranscripts(type: .dictation, limit: limit)
    }

    func recentMeetings(limit: Int = 8) throws -> [TranscriptRecord] {
        try recentTranscripts(type: .meeting, limit: limit)
    }

    private func recentTranscripts(type: TranscriptRecord.TranscriptType, limit: Int) throws -> [TranscriptRecord] {
        let sql = """
        SELECT id, type, created_at, duration_seconds, raw_text, polished_text, audio_path, model_used, status
        FROM transcripts
        WHERE type = ?
        ORDER BY created_at DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        bind(type.rawValue, to: statement, index: 1)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var records: [TranscriptRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let record = makeRecord(from: statement) else { continue }
            records.append(record)
        }
        return records
    }

    func save(_ record: TranscriptRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO transcripts (
            id,
            type,
            created_at,
            duration_seconds,
            raw_text,
            polished_text,
            audio_path,
            model_used,
            language,
            status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        bind(record.id.uuidString, to: statement, index: 1)
        bind(record.type.rawValue, to: statement, index: 2)
        sqlite3_bind_double(statement, 3, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, record.durationSeconds)
        bind(record.rawText, to: statement, index: 5)
        bind(record.polishedText, to: statement, index: 6)
        bind(record.audioURL.path, to: statement, index: 7)
        bind(record.modelUsed, to: statement, index: 8)
        bind("en", to: statement, index: 9)
        bind(record.status, to: statement, index: 10)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WalkyError.storage(lastErrorMessage)
        }
    }

    func markAudioDeleted(for id: UUID) throws {
        let sql = """
        UPDATE transcripts
        SET status = 'deleted_audio', audio_path = NULL
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        bind(id.uuidString, to: statement, index: 1)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WalkyError.storage(lastErrorMessage)
        }
    }

    func markMeetingAudioDeleted(for id: UUID) throws {
        try markAudioDeleted(for: id)
    }

    func deleteTranscript(id: UUID) throws {
        let sql = """
        DELETE FROM transcripts
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        bind(id.uuidString, to: statement, index: 1)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WalkyError.storage(lastErrorMessage)
        }
    }

    func deleteMeeting(id: UUID) throws {
        let deleteSegments = """
        DELETE FROM meeting_segments
        WHERE meeting_id = ?;
        """

        var segmentStatement: OpaquePointer?
        try prepare(deleteSegments, statement: &segmentStatement)
        defer { sqlite3_finalize(segmentStatement) }
        bind(id.uuidString, to: segmentStatement, index: 1)

        guard sqlite3_step(segmentStatement) == SQLITE_DONE else {
            throw WalkyError.storage(lastErrorMessage)
        }

        try deleteTranscript(id: id)
    }

    func saveSegment(_ segment: MeetingSegment) throws {
        let sql = """
        INSERT OR REPLACE INTO meeting_segments (
            meeting_id,
            segment_index,
            start_time,
            end_time,
            raw_text,
            polished_text,
            status,
            audio_chunk_path
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        bind(segment.meetingID.uuidString, to: statement, index: 1)
        sqlite3_bind_int(statement, 2, Int32(segment.segmentIndex))
        sqlite3_bind_double(statement, 3, segment.startTime)
        sqlite3_bind_double(statement, 4, segment.endTime)
        bind(segment.rawText, to: statement, index: 5)
        bind(segment.polishedText, to: statement, index: 6)
        bind(segment.status, to: statement, index: 7)
        bind(segment.audioChunkURL.path, to: statement, index: 8)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WalkyError.storage(lastErrorMessage)
        }
    }

    func segments(for meetingID: UUID) throws -> [MeetingSegment] {
        let sql = """
        SELECT meeting_id, segment_index, start_time, end_time, raw_text, polished_text, status, audio_chunk_path
        FROM meeting_segments
        WHERE meeting_id = ?
        ORDER BY segment_index ASC;
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        bind(meetingID.uuidString, to: statement, index: 1)

        var segments: [MeetingSegment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let meetingIDText = columnText(statement, 0),
                let meetingID = UUID(uuidString: meetingIDText),
                let rawText = columnText(statement, 4),
                let polishedText = columnText(statement, 5),
                let status = columnText(statement, 6),
                let audioPath = columnText(statement, 7)
            else {
                continue
            }

            segments.append(
                MeetingSegment(
                    meetingID: meetingID,
                    segmentIndex: Int(sqlite3_column_int(statement, 1)),
                    startTime: sqlite3_column_double(statement, 2),
                    endTime: sqlite3_column_double(statement, 3),
                    rawText: rawText,
                    polishedText: polishedText,
                    status: status,
                    audioChunkURL: URL(fileURLWithPath: audioPath)
                )
            )
        }
        return segments
    }

    func recoverableMeetingIDs() throws -> [UUID] {
        let sql = """
        SELECT DISTINCT meeting_id
        FROM meeting_segments
        WHERE meeting_id NOT IN (
            SELECT id FROM transcripts WHERE type = 'meeting'
        )
        ORDER BY meeting_id ASC;
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        var ids: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let idText = columnText(statement, 0), let id = UUID(uuidString: idText) {
                ids.append(id)
            }
        }
        return ids
    }

    private func open() throws {
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw WalkyError.storage(lastErrorMessage)
        }
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS transcripts (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            created_at REAL NOT NULL,
            duration_seconds REAL NOT NULL,
            raw_text TEXT NOT NULL,
            polished_text TEXT NOT NULL,
            audio_path TEXT,
            model_used TEXT NOT NULL,
            source_app TEXT,
            language TEXT NOT NULL DEFAULT 'en',
            status TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_transcripts_type_created_at
        ON transcripts(type, created_at DESC);

        CREATE TABLE IF NOT EXISTS meeting_segments (
            meeting_id TEXT NOT NULL,
            segment_index INTEGER NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            raw_text TEXT NOT NULL,
            polished_text TEXT NOT NULL,
            status TEXT NOT NULL,
            audio_chunk_path TEXT,
            PRIMARY KEY (meeting_id, segment_index)
        );
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw WalkyError.storage(lastErrorMessage)
        }
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw WalkyError.storage(lastErrorMessage)
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func makeRecord(from statement: OpaquePointer?) -> TranscriptRecord? {
        guard
            let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
            let typeRaw = columnText(statement, 1),
            let type = TranscriptRecord.TranscriptType(rawValue: typeRaw),
            let rawText = columnText(statement, 4),
            let polishedText = columnText(statement, 5),
            let modelUsed = columnText(statement, 7),
            let status = columnText(statement, 8)
        else {
            return nil
        }

        let audioPath = columnText(statement, 6) ?? ""

        return TranscriptRecord(
            id: id,
            type: type,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            durationSeconds: sqlite3_column_double(statement, 3),
            rawText: rawText,
            polishedText: polishedText,
            audioURL: URL(fileURLWithPath: audioPath),
            modelUsed: modelUsed,
            status: status
        )
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private var lastErrorMessage: String {
        if let database, let message = sqlite3_errmsg(database) {
            return String(cString: message)
        }
        return "sqlite operation failed."
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
