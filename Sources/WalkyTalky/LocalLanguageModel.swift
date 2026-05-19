import Foundation

struct LocalLanguageModel {
    enum RuntimeStatus: Equatable {
        case available(String)
        case unavailable

        var title: String {
            switch self {
            case .available(let name):
                "local llm available: \(name.lowercased())"
            case .unavailable:
                "no local llm runtime found"
            }
        }
    }

    func status() -> RuntimeStatus {
        if findExecutable("ollama") != nil {
            return .available("ollama")
        }
        if findExecutable("llama-cli") != nil {
            return .available("llama.cpp")
        }
        return .unavailable
    }

    func refine(_ text: String) async throws -> String {
        if let ollama = findExecutable("ollama") {
            return try await runOllama(ollama, text: text)
        }

        throw WalkyError.transcription(
            "no local llm runtime found. install ollama or make llama-cli available on path to enable optional local llm polishing."
        )
    }

    private func runOllama(_ executable: URL, text: String) async throws -> String {
        let prompt = """
        Clean this transcript locally. Preserve meaning. Do not invent facts. Keep names and numbers unchanged. Return only the cleaned transcript.

        \(text)
        """

        let process = Process()
        process.executableURL = executable
        process.arguments = ["run", "llama3.2", prompt]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0, !outputText.isEmpty else {
            throw WalkyError.transcription(errorText.isEmpty ? "local llm returned no text." : errorText.lowercased())
        }

        return outputText
    }

    private func findExecutable(_ name: String) -> URL? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        let commonPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        return commonPaths
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }
}
