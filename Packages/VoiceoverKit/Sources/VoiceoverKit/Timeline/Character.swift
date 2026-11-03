import Foundation

/// A speaker in the video. Takes belong to a character; the character decides which ElevenLabs voice
/// they end up with and how expressively it performs.
public struct Character: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var voice: Voice?
    public var settings: VoiceSettings
    /// Index into the app's colour palette, so each character is recognisable on the timeline.
    public var colorIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        voice: Voice? = nil,
        settings: VoiceSettings = .expressive,
        colorIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.voice = voice
        self.settings = settings
        self.colorIndex = colorIndex
    }
}
