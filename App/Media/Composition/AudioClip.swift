import AVFoundation
import UIKit
import VoiceoverKit

/// What an audio track carries, so the mix can set one level per kind.
nonisolated enum AudioKind: Hashable, Sendable {
    case original, voice, effect, music
}

/// One piece of audio laid over the video.
nonisolated struct AudioClip: Equatable, Sendable {
    let url: URL
    let kind: AudioKind
    /// Position on the video's timeline.
    let start: Double
    /// Where to begin inside the file.
    let sourceOffset: Double
    /// Nil plays the file to its end (or the video's end, whichever is first).
    let duration: Double?

    init(url: URL, kind: AudioKind, start: Double = 0, sourceOffset: Double = 0, duration: Double? = nil) {
        self.url = url
        self.kind = kind
        self.start = start
        self.sourceOffset = sourceOffset
        self.duration = duration
    }
}
