import Foundation

/// Sound design suggested for a video: effects at points on its timeline and one prompt for background
/// music. Nothing here has been generated yet; generating each piece is a separate ElevenLabs call.
public struct SoundPlan: Equatable, Sendable {
    public struct Effect: Equatable, Sendable, Identifiable {
        /// Position in the plan, in time order.
        public let id: Int
        /// Second on the video's timeline where the sound starts.
        public var start: Double
        /// Seconds of sound to ask ElevenLabs for.
        public var duration: Double
        /// What the sound is, as a sound-effect prompt.
        public var prompt: String
        /// The words in the video that call for it, so the suggestion can be judged at a glance.
        public var cue: String

        public init(id: Int, start: Double, duration: Double, prompt: String, cue: String = "") {
            self.id = id
            self.start = start
            self.duration = duration
            self.prompt = prompt
            self.cue = cue
        }
    }

    public var effects: [Effect]
    /// A prompt for instrumental background music; empty until the model gets to it.
    public var musicPrompt: String

    public init(effects: [Effect] = [], musicPrompt: String = "") {
        self.effects = effects
        self.musicPrompt = musicPrompt
    }

    /// The most effects a plan keeps. Each one costs credits to generate, and a short clip rarely needs more.
    public static let maximumEffects = 6
    /// Lengths ElevenLabs sound generation accepts.
    public static let effectLength: ClosedRange<Double> = 0.5...22

    /// The plan made safe to act on for a video `videoDuration` seconds long. A small model's numbers are
    /// suggestions: starts are pulled inside the video, lengths into what the API accepts and not past the
    /// end, blank prompts and repeats are dropped, and the rest is put in time order and renumbered.
    public func fitted(to videoDuration: Double) -> SoundPlan {
        var seen = Set<String>()
        let kept = effects.compactMap { effect -> Effect? in
            let prompt = effect.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, effect.start.isFinite, effect.duration.isFinite,
                  seen.insert(prompt.lowercased()).inserted else { return nil }
            let latestStart = max(videoDuration - Self.effectLength.lowerBound, 0)
            let start = min(max(effect.start, 0), latestStart)
            let room = max(videoDuration - start, Self.effectLength.lowerBound)
            let duration = min(min(max(effect.duration, Self.effectLength.lowerBound), Self.effectLength.upperBound), room)

            return Effect(id: 0, start: start, duration: duration, prompt: prompt, cue: effect.cue)
        }

        let ordered = kept.prefix(Self.maximumEffects).sorted { $0.start < $1.start }

        return SoundPlan(
            effects: ordered.enumerated().map { index, effect in
                Effect(id: index, start: effect.start, duration: effect.duration, prompt: effect.prompt, cue: effect.cue)
            },
            musicPrompt: musicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
