import Foundation

struct WhisperTranscriber {
    let paths: WalkyPaths
    static let preferredModelKey = "walkyTalky.preferredModelName"

    var selectedModelName: String {
        selectedModelURL?.lastPathComponent ?? "missing"
    }

    private var selectedModelURL: URL? {
        if
            let preferred = UserDefaults.standard.string(forKey: Self.preferredModelKey),
            !preferred.isEmpty
        {
            let preferredURL = paths.models.appendingPathComponent(preferred)
            if FileManager.default.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }
        }

        let candidates = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3-turbo-q5_0.bin",
            "ggml-medium.bin",
            "ggml-medium.en.bin",
            "ggml-small.bin",
            "ggml-small.en.bin",
            "ggml-base.en.bin",
            "ggml-base.bin"
        ]

        return candidates
            .map { paths.models.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func availableModels() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: paths.models, includingPropertiesForKeys: nil) else {
            return []
        }

        return contents
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
            .sorted()
    }

    func transcribe(_ audioURL: URL, tinydiarize: Bool = false) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WalkyError.transcription("the local audio file is missing.")
        }

        guard let whisperBinary = findWhisperBinary() else {
            throw WalkyError.transcription(
                "install or build whisper.cpp, then place the binary at ~/library/application support/walky talky/whisper or make whisper-cli available on path."
            )
        }

        guard let modelURL = selectedModelURL else {
            throw WalkyError.transcription(
                "add a local whisper model to ~/library/application support/walky talky/models/."
            )
        }

        let process = Process()
        process.executableURL = whisperBinary
        var arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-nt",
            "-np",
            "-t", "\(max(4, min(ProcessInfo.processInfo.activeProcessorCount, 8)))"
        ]
        if tinydiarize {
            guard modelURL.lastPathComponent.contains("tdrz") else {
                throw WalkyError.transcription(
                    "tinydiarize needs a local tdrz whisper model such as ggml-small.en-tdrz.bin."
                )
            }
            arguments.append("-tdrz")
        }
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "whisper.cpp exited with an error."
            throw WalkyError.transcription(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            throw WalkyError.transcription("local transcription returned no text.")
        }

        return text
    }

    private func findWhisperBinary() -> URL? {
        let localBinary = paths.root.appendingPathComponent("whisper")
        if FileManager.default.isExecutableFile(atPath: localBinary.path) {
            return localBinary
        }

        for name in ["whisper-cli", "main"] {
            if let path = findExecutableOnPath(name) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func findExecutableOnPath(_ name: String) -> String? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
