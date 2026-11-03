import AVFoundation
import UIKit
import VoiceoverKit

/// Levels per kind, 0...1.
nonisolated struct MixLevels: Equatable, Codable, Sendable {
    var original: Float = 0.25
    var voice: Float = 1
    var effect: Float = 0.8

    func level(for kind: AudioKind) -> Float {
        switch kind {
        case .original: original
        case .voice: voice
        case .effect: effect
        }
    }
}
