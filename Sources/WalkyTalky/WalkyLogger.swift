import Foundation

struct WalkyLogger {
    private let fileURL: URL

    init(paths: WalkyPaths) {
        fileURL = paths.logs.appendingPathComponent("walky.log")
    }

    func write(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    return
                }
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
