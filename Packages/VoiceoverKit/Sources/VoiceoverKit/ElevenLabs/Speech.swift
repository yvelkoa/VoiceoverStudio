import Foundation

/// Per-character timing returned by `text-to-speech/{voice_id}/with-timestamps`.
public struct CharacterAlignment: Decodable, Equatable, Sendable {
    public let characters: [String]
    public let startTimes: [Double]
    public let endTimes: [Double]

    public init(characters: [String], startTimes: [Double], endTimes: [Double]) {
        self.characters = characters
        self.startTimes = startTimes
        self.endTimes = endTimes
    }

    enum CodingKeys: String, CodingKey {
        case characters
        case startTimes = "character_start_times_seconds"
        case endTimes = "character_end_times_seconds"
    }
}

/// Generated speech: encoded audio (MP3) plus the timing of every character in the script.
public struct Speech: Sendable {
    public let audio: Data
    public let alignment: CharacterAlignment
}

struct SpeechResponse: Decodable {
    let audioBase64: String
    let alignment: CharacterAlignment?
    let normalizedAlignment: CharacterAlignment?

    enum CodingKeys: String, CodingKey {
        case audioBase64 = "audio_base64"
        case alignment
        case normalizedAlignment = "normalized_alignment"
    }
}
