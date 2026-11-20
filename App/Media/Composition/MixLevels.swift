import AVFoundation
import UIKit
import VoiceoverKit

/// Levels per kind, 0...1.
nonisolated struct MixLevels: Equatable, Codable, Sendable {
    var original: Float = 0.25
    var voice: Float = 1
    var effect: Float = 0.8
    /// Low by default: music sits under the voice, not next to it.
    var music: Float = 0.3

    init() {}

    /// Hand-written so a manifest saved before a level existed keeps its other levels (see `ProjectDocument`).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MixLevels()
        original = try c.decodeIfPresent(Float.self, forKey: .original) ?? defaults.original
        voice = try c.decodeIfPresent(Float.self, forKey: .voice) ?? defaults.voice
        effect = try c.decodeIfPresent(Float.self, forKey: .effect) ?? defaults.effect
        music = try c.decodeIfPresent(Float.self, forKey: .music) ?? defaults.music
    }

    func level(for kind: AudioKind) -> Float {
        switch kind {
        case .original:
            original
        case .voice:
            voice
        case .effect:
            effect
        case .music:
            music
        }
    }
}
