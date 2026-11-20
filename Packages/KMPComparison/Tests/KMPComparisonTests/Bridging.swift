import Foundation
import Shared
import VoiceoverKit

// Both modules declare `Caption`, `TimedWord`, `Take`… so every use is module-qualified.
// The conversions below are the glue an app would need at the boundary if it adopted the framework.

/// A plain-value picture of a caption that both implementations can be reduced to and compared by.
struct CaptionSnapshot: Equatable, CustomStringConvertible {
    let id: Int
    let text: String
    let start: Double
    let end: Double
    let track: Int

    init(_ caption: VoiceoverKit.Caption) {
        (id, text, start, end, track) = (caption.id, caption.text, caption.start, caption.end, caption.track)
    }

    init(_ caption: Shared.Caption) {
        (id, text, start, end, track) = (Int(caption.id), caption.text, caption.start, caption.end, Int(caption.track))
    }

    var description: String { "#\(id) [\(track)] \(start)–\(end) \"\(text)\"" }
}

struct SegmentSnapshot: Equatable {
    let takeID: String
    let characterID: String
    let start: Double
    let sourceOffset: Double
    let duration: Double

    init(_ segment: VoiceoverKit.AudioSegment) {
        takeID = segment.takeID.uuidString.lowercased()
        characterID = segment.characterID.uuidString.lowercased()
        (start, sourceOffset, duration) = (segment.start, segment.sourceOffset, segment.duration)
    }

    init(_ segment: Shared.AudioSegment) {
        takeID = segment.takeId.description()
        characterID = segment.characterId.description()
        (start, sourceOffset, duration) = (segment.start, segment.sourceOffset, segment.duration)
    }
}

extension VoiceoverKit.TimedWord {
    var kotlin: Shared.TimedWord { Shared.TimedWord(text: text, start: start, end: end) }
}

extension Shared.TimedWord {
    var swift: VoiceoverKit.TimedWord { VoiceoverKit.TimedWord(text: text, start: start, end: end) }
}

extension VoiceoverKit.CharacterAlignment {
    var kotlin: Shared.CharacterAlignment {
        // `List<Double>` arrives in Swift as `[KotlinDouble]`: every element is boxed by hand.
        Shared.CharacterAlignment(
            characters: characters,
            startTimes: startTimes.map { KotlinDouble(value: $0) },
            endTimes: endTimes.map { KotlinDouble(value: $0) }
        )
    }
}

extension UUID {
    /// Foundation's `UUID` and Kotlin's `Uuid` are unrelated types; the string form is the bridge.
    var kotlin: KotlinUuid { KotlinUuid.companion.parse(uuidString: uuidString) }
}

extension VoiceoverKit.Take {
    var kotlin: Shared.Take {
        Shared.Take(
            id: id.kotlin,
            characterId: characterID.kotlin,
            start: start,
            duration: duration,
            recording: recording.path,
            sequence: Int32(sequence)
        )
    }
}

/// Small deterministic generator, so a failure reproduces.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
