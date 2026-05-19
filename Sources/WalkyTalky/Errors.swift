import Foundation

enum WalkyError: LocalizedError {
    case recording(String)
    case transcription(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .recording(let message), .transcription(let message), .storage(let message):
            message
        }
    }
}

