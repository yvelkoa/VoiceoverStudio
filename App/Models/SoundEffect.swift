import Foundation
import Observation
import VoiceoverKit

/// A generated sound placed on the timeline. Generated once, kept on disk; moving it never calls the API.
struct SoundEffect: Identifiable, Equatable, Sendable {
    let id: UUID
    var prompt: String
    var start: Double
    let duration: Double
    let audio: URL

    var end: Double { start + duration }
}
