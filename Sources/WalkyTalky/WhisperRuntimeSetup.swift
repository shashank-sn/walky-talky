import AppKit
import Foundation

struct WhisperModelOption: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let fileName: String
    let size: String
    let minimumBytes: Int64
    let sourceURL: URL
}

@MainActor
final class WhisperRuntimeSetup: ObservableObject {
    @Published private(set) var runtimeInstalled = false
    @Published private(set) var runtimeDetail = "checking local whisper"
    @Published private(set) var installedModelNames: Set<String> = []
    @Published var selectedModelID: String
    @Published private(set) var status = "choose a local model"
    @Published private(set) var isWorking = false

    static let modelOptions: [WhisperModelOption] = [
        WhisperModelOption(
            id: "large-v3-turbo",
            name: "large v3 turbo",
            detail: "recommended for accent handling and cleaner dictation.",
            fileName: "ggml-large-v3-turbo.bin",
            size: "about 1.5 gb",
            minimumBytes: 1_000_000_000,
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
        ),
        WhisperModelOption(
            id: "base-en",
            name: "base english",
            detail: "small fallback for quick setup and low storage use.",
            fileName: "ggml-base.en.bin",
            size: "about 141 mb",
            minimumBytes: 100_000_000,
            sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!
        ),
        WhisperModelOption(
            id: "small-tdrz",
            name: "small tdrz",
            detail: "optional meeting model with tinydiarize support.",
            fileName: "ggml-small.en-tdrz.bin",
            size: "about 465 mb",
            minimumBytes: 350_000_000,
            sourceURL: URL(string: "https://huggingface.co/akashmjn/tinydiarize-whisper.cpp/resolve/main/ggml-small.en-tdrz.bin")!
        )
    ]

    private let paths: WalkyPaths
    private let fileManager: FileManager

    init(paths: WalkyPaths = .default, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager

        if
            let preferred = UserDefaults.standard.string(forKey: WhisperTranscriber.preferredModelKey),
            let matching = Self.modelOptions.first(where: { $0.fileName == preferred })
        {
            selectedModelID = matching.id
        } else {
            selectedModelID = "large-v3-turbo"
        }

        refresh()
    }

    var selectedOption: WhisperModelOption {
        Self.modelOptions.first { $0.id == selectedModelID } ?? Self.modelOptions[0]
    }

    var selectedModelInstalled: Bool {
        installedModelNames.contains(selectedOption.fileName)
    }

    var ready: Bool {
        runtimeInstalled && selectedModelInstalled
    }

    func refresh() {
        runtimeInstalled = findWhisperBinary() != nil
        runtimeDetail = runtimeInstalled
            ? "installed outside the app"
            : "missing local whisper runtime"

        let contents = (try? fileManager.contentsOfDirectory(at: paths.models, includingPropertiesForKeys: nil)) ?? []
        installedModelNames = Set(contents.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("ggml-"), name.hasSuffix(".bin") else { return nil }
            if let option = Self.modelOptions.first(where: { $0.fileName == name }) {
                return modelIsValid(at: url, option: option) ? name : nil
            }
            return modelSize(at: url) > 1_000_000 ? name : nil
        })

        if selectedModelInstalled {
            UserDefaults.standard.set(selectedOption.fileName, forKey: WhisperTranscriber.preferredModelKey)
            status = "\(selectedOption.name) installed"
        } else if installedModelNames.isEmpty {
            status = "no local model installed yet"
        } else {
            status = "\(selectedOption.name) not installed"
        }
    }

    func choose(_ option: WhisperModelOption) {
        selectedModelID = option.id
        if installedModelNames.contains(option.fileName) {
            UserDefaults.standard.set(option.fileName, forKey: WhisperTranscriber.preferredModelKey)
            status = "\(option.name) installed"
        } else {
            status = "\(option.name) not installed"
        }
    }

    func installSelectedModel() async {
        let option = selectedOption

        if installedModelNames.contains(option.fileName) {
            UserDefaults.standard.set(option.fileName, forKey: WhisperTranscriber.preferredModelKey)
            status = "\(option.name) installed"
            return
        }

        isWorking = true
        status = "downloading \(option.name)"

        do {
            try paths.ensureCreated(fileManager: fileManager)
            let destination = paths.models.appendingPathComponent(option.fileName)
            let partial = destination.deletingLastPathComponent().appendingPathComponent(".\(option.fileName).download")
            if fileManager.fileExists(atPath: partial.path) {
                try fileManager.removeItem(at: partial)
            }

            let (temporaryURL, response) = try await URLSession.shared.download(from: option.sourceURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw WalkyError.transcription("model download failed with http \(http.statusCode).")
            }

            try fileManager.moveItem(at: temporaryURL, to: partial)
            let size = modelSize(at: partial)
            guard size >= option.minimumBytes else {
                throw WalkyError.transcription("downloaded model is too small to be valid.")
            }

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: partial, to: destination)
            UserDefaults.standard.set(option.fileName, forKey: WhisperTranscriber.preferredModelKey)
            refresh()
            status = "\(option.name) installed"
        } catch {
            status = "download failed: \(error.localizedDescription.lowercased())"
        }

        isWorking = false
    }

    func openRuntimeFolder() {
        try? paths.ensureCreated(fileManager: fileManager)
        NSWorkspace.shared.open(paths.root)
    }

    func openModelsFolder() {
        try? paths.ensureCreated(fileManager: fileManager)
        NSWorkspace.shared.open(paths.models)
    }

    private func findWhisperBinary() -> URL? {
        let localBinary = paths.root.appendingPathComponent("whisper")
        if fileManager.isExecutableFile(atPath: localBinary.path) {
            return localBinary
        }

        for name in ["whisper-cli", "main"] {
            if let path = findExecutableOnPath(name) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func modelIsValid(at url: URL, option: WhisperModelOption) -> Bool {
        modelSize(at: url) >= option.minimumBytes
    }

    private func modelSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func findExecutableOnPath(_ name: String) -> String? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let path = "\(directory)/\(name)"
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
