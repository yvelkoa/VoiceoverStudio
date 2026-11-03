import Foundation

/// A voice available to the account (`GET /v1/voices`).
public struct Voice: Codable, Identifiable, Hashable, Sendable {
    public let voiceID: String
    public let name: String
    public let category: String?
    public let labels: [String: String]
    public let previewURL: URL?

    public var id: String { voiceID }

    /// Short human-readable description built from labels, e.g. "american · young · female".
    public var summary: String {
        ["accent", "age", "gender", "use_case"]
            .compactMap { labels[$0] }
            .joined(separator: " · ")
    }

    public init(voiceID: String, name: String, category: String? = nil, labels: [String: String] = [:], previewURL: URL? = nil) {
        self.voiceID = voiceID
        self.name = name
        self.category = category
        self.labels = labels
        self.previewURL = previewURL
    }

    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id", name, category, labels, previewURL = "preview_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voiceID = try c.decode(String.self, forKey: .voiceID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        // Labels are free-form; a single non-string value must not fail the whole voice list.
        labels = (try? c.decodeIfPresent([String: String].self, forKey: .labels)) ?? [:]
        previewURL = try? c.decodeIfPresent(URL.self, forKey: .previewURL)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(voiceID, forKey: .voiceID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encode(labels, forKey: .labels)
        try c.encodeIfPresent(previewURL, forKey: .previewURL)
    }
}

struct VoicesResponse: Decodable {
    let voices: [Voice]
}

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
