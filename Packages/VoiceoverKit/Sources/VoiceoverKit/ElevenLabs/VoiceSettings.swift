import Foundation

/// Per-request overrides for how a voice performs. Nil fields keep the voice's stored defaults.
public struct VoiceSettings: Codable, Equatable, Sendable {
    /// 0...1. Lower gives a wider emotional range, higher sounds steadier but flatter.
    public var stability: Double?
    /// 0...1. How closely the output sticks to the original voice.
    public var similarityBoost: Double?
    /// 0...1. Exaggerates the speaker's style; non-zero costs latency.
    public var style: Double?
    /// 0.7...1.2. 1.0 is the voice's natural pace.
    public var speed: Double?
    public var useSpeakerBoost: Bool?

    public init(
        stability: Double? = nil,
        similarityBoost: Double? = nil,
        style: Double? = nil,
        speed: Double? = nil,
        useSpeakerBoost: Bool? = nil
    ) {
        self.stability = stability
        self.similarityBoost = similarityBoost
        self.style = style
        self.speed = speed
        self.useSpeakerBoost = useSpeakerBoost
    }

    /// Steady, narrator-like delivery.
    public static let narration = VoiceSettings(stability: 0.75, similarityBoost: 0.75, style: 0)
    /// Follows the source performance closely; the default for voice conversion.
    public static let expressive = VoiceSettings(stability: 0.3, similarityBoost: 0.8, style: 0.4)

    /// The same keys as the JSON encoding, for embedding in a larger request body.
    var jsonObject: [String: any Sendable] {
        var object: [String: any Sendable] = [:]
        object[CodingKeys.stability.rawValue] = stability
        object[CodingKeys.similarityBoost.rawValue] = similarityBoost
        object[CodingKeys.style.rawValue] = style
        object[CodingKeys.speed.rawValue] = speed
        object[CodingKeys.useSpeakerBoost.rawValue] = useSpeakerBoost

        return object
    }

    enum CodingKeys: String, CodingKey {
        case stability
        case similarityBoost = "similarity_boost"
        case style
        case speed
        case useSpeakerBoost = "use_speaker_boost"
    }
}
