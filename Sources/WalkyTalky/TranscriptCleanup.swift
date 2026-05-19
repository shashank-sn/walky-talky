import Foundation

struct TranscriptCleanup {
    func polish(_ text: String, dictionary: [CustomDictionaryEntry] = []) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = replaceSpokenPunctuation(in: result)
        result = removeConservativeFillers(in: result)
        result = normalizePunctuationSpacing(result)
        result = paragraphize(result)
        result = applyDictionary(dictionary, to: result)
        return result.lowercased()
    }

    private func applyDictionary(_ dictionary: [CustomDictionaryEntry], to text: String) -> String {
        var result = text
        for entry in dictionary.sorted(by: { $0.spoken.count > $1.spoken.count }) {
            let spoken = entry.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty, !replacement.isEmpty else { continue }
            result = result.replacingOccurrences(
                of: spoken,
                with: replacement,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
        return result
    }

    private func replaceSpokenPunctuation(in text: String) -> String {
        var result = text
        let replacements = [
            " comma": ",",
            " period": ".",
            " full stop": ".",
            " question mark": "?",
            " exclamation mark": "!",
            " colon": ":",
            " semicolon": ";",
            " dash": " - ",
            " new line": "\n",
            " next line": "\n",
            " new paragraph": "\n\n",
            " next paragraph": "\n\n"
        ]

        for (spoken, punctuation) in replacements {
            result = result.replacingOccurrences(
                of: spoken,
                with: punctuation,
                options: [.caseInsensitive]
            )
        }
        return result
    }

    private func normalizePunctuationSpacing(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"\s+([,.;:?!])"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"([,;:])([^\s])"#, with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: #"([.?!])([A-Za-z])"#, with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n\s+"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+\n"#, with: "\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeConservativeFillers(in text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"(?i)\b(um|uh)[, ]+"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\b(like),\s+\1\b"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func paragraphize(_ text: String) -> String {
        if text.contains("\n") {
            return text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        let pattern = #"[^.?!]+[.?!]"#
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = (try? NSRegularExpression(pattern: pattern))?.matches(in: text, range: range) ?? []
        let sentences = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard sentences.count > 4 else { return text }

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
}
