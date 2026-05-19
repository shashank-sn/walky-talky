import Foundation

struct WalkyPaths {
    static let `default` = WalkyPaths()

    let root: URL
    let models: URL
    let recordings: URL
    let dictationRecordings: URL
    let meetingRecordings: URL
    let exports: URL
    let meetingTranscripts: URL
    let transcriptsDatabase: URL
    let logs: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = appSupport.appendingPathComponent("Walky Talky", isDirectory: true)
        models = root.appendingPathComponent("models", isDirectory: true)
        recordings = root.appendingPathComponent("recordings", isDirectory: true)
        dictationRecordings = recordings.appendingPathComponent("dictation", isDirectory: true)
        meetingRecordings = recordings.appendingPathComponent("meetings", isDirectory: true)
        exports = root.appendingPathComponent("exports", isDirectory: true)
        meetingTranscripts = exports.appendingPathComponent("meetings", isDirectory: true)
        transcriptsDatabase = root.appendingPathComponent("transcripts.sqlite")
        logs = root.appendingPathComponent("logs", isDirectory: true)
    }

    func ensureCreated(fileManager: FileManager = .default) throws {
        for directory in [root, models, recordings, dictationRecordings, meetingRecordings, exports, meetingTranscripts, logs] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
