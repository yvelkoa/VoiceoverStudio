import Foundation

/// One generated instrumental track under the whole video, from its first second. Generated once at the
/// video's length and kept on disk; one per project, a new one replaces it.
struct BackgroundMusic: Identifiable, Equatable, Sendable {
    let id: UUID
    let prompt: String
    let duration: Double
    let audio: URL

    init(id: UUID = UUID(), prompt: String, duration: Double, audio: URL) {
        self.id = id
        self.prompt = prompt
        self.duration = duration
        self.audio = audio
    }
}
