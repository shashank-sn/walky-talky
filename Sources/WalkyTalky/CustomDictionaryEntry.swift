import Foundation

struct CustomDictionaryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var spoken: String
    var replacement: String

    init(id: UUID = UUID(), spoken: String, replacement: String) {
        self.id = id
        self.spoken = spoken.lowercased()
        self.replacement = replacement.lowercased()
    }
}
