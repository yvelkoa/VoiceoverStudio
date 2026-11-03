import Foundation
import VoiceoverKit

/// Record takes with the microphone, or type a script for ElevenLabs to read.
nonisolated enum EditingMode: String, Codable, Hashable {
    case record, type
}
