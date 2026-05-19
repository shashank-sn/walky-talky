import Foundation

struct WalkyIntelligenceResult {
    let title: String
    let summary: [String]
    let actionItems: [String]
    let cleanedText: String

    var markdown: String {
        var sections = ["# \(title.lowercased())"]

        if !summary.isEmpty {
            sections.append("## summary\n\n" + summary.map { "- \($0.lowercased())" }.joined(separator: "\n"))
        }

        if !actionItems.isEmpty {
            sections.append("## action items\n\n" + actionItems.map { "- \($0.lowercased())" }.joined(separator: "\n"))
        }

        sections.append("## cleaned transcript\n\n\(cleanedText.lowercased())")
        return sections.joined(separator: "\n\n")
    }
}

struct WalkyIntelligence {
    enum Preset: String, CaseIterable, Identifiable {
        case paragraphs = "paragraphs"
        case bullets = "bullets"
        case compact = "compact"

        var id: String { rawValue }
    }

    func analyze(_ record: TranscriptRecord, preset: Preset = .paragraphs) -> WalkyIntelligenceResult {
        let source = record.polishedText.isEmpty ? record.rawText : record.polishedText
        let cleaned = clean(source, preset: preset)
        let sentences = splitSentences(cleaned)
        let summary = summarize(sentences)
        let actionItems = extractActionItems(sentences)

        return WalkyIntelligenceResult(
            title: record.type == .meeting ? "walky talky meeting intelligence" : "walky talky dictation intelligence",
            summary: summary,
            actionItems: actionItems,
            cleanedText: cleaned
        )
    }

    private func clean(_ text: String, preset: Preset) -> String {
        switch preset {
        case .paragraphs:
            paragraphize(text)
        case .bullets:
            splitSentences(text).map { "- \($0)" }.joined(separator: "\n")
        case .compact:
            splitSentences(text).joined(separator: " ")
        }
    }

    private func paragraphize(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }

        let sentences = splitSentences(normalized)
        var paragraphs: [String] = []
        var current: [String] = []

        for sentence in sentences {
            current.append(sentence)
            if current.count == 3 {
                paragraphs.append(current.joined(separator: " "))
                current.removeAll()
            }
        }

        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func splitSentences(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { sentence in
                sentence.last.map { ".?!".contains($0) } == true ? sentence : "\(sentence)."
            }
    }

    private func summarize(_ sentences: [String]) -> [String] {
        guard !sentences.isEmpty else { return [] }

        var chosen: [String] = []
        if let first = sentences.first {
            chosen.append(first)
        }

        let scored = sentences
            .dropFirst()
            .map { sentence in
                (sentence, score(sentence))
            }
            .sorted { left, right in
                left.1 == right.1 ? left.0.count > right.0.count : left.1 > right.1
            }

        for (sentence, score) in scored where score > 0 && chosen.count < 5 {
            if !chosen.contains(sentence) {
                chosen.append(sentence)
            }
        }

        return Array(chosen.prefix(5))
    }

    private func extractActionItems(_ sentences: [String]) -> [String] {
        let markers = [
            "need to",
            "needs to",
            "should",
            "todo",
            "to do",
            "follow up",
            "next step",
            "action item",
            "remember to",
            "we will",
            "i will"
        ]

        return sentences.filter { sentence in
            let lower = sentence.lowercased()
            return markers.contains { lower.contains($0) }
        }
        .prefix(8)
        .map { $0 }
    }

    private func score(_ sentence: String) -> Int {
        let lower = sentence.lowercased()
        let keywords = [
            "decision",
            "important",
            "problem",
            "issue",
            "risk",
            "blocked",
            "next",
            "need",
            "should",
            "meeting",
            "customer",
            "product",
            "launch"
        ]

        return keywords.reduce(0) { score, keyword in
            lower.contains(keyword) ? score + 1 : score
        }
    }
}
