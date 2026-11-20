import Foundation
import FoundationModels

/// Suggests sound effects and a music prompt from what is said in a video, using the Apple Intelligence
/// model on the device: free, offline, and the transcript never leaves the phone.
///
/// The on-device model is small (a 4096-token window shared by instructions, transcript and answer) and
/// speaks a limited set of languages, so its plan is a starting point the user reviews, and everything it
/// returns goes through `SoundPlan.fitted(to:)` before it is shown.
public enum SoundDirector {

    /// Why suggestions can't run here right now, or nil when the model is ready. Checked before every plan;
    /// a request can still fail afterwards (the simulator reports the model as available but refuses to run it).
    public static var unavailability: SoundDirectorError? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceOff
        case .unavailable(.modelNotReady):
            .modelNotReady
        case .unavailable:
            .deviceNotEligible
        }
    }

    /// Whether the model can read `locale`. Unsupported languages fail the request anyway; asking first
    /// gives a clearer message than the model's error.
    public static func supports(_ locale: Locale) -> Bool {
        SystemLanguageModel.default.supportsLocale(locale)
    }

    /// Loads the model ahead of a request. The first request after the model was unloaded otherwise waits
    /// around ten seconds before the first word.
    public static func prewarm() {
        guard unavailability == nil else { return }

        LanguageModelSession(instructions: instructions).prewarm()
    }

    /// Streams the plan as the model writes it: each element is the whole plan so far, already fitted to the
    /// video. The last element is the finished plan. Fails with a `SoundDirectorError`.
    ///
    /// - Parameter locale: the language the words are in, when it is known (the recording language);
    ///   nil skips the up-front language check.
    public static func plan(
        for captions: [Caption],
        videoDuration: Double,
        locale: Locale?
    ) -> AsyncThrowingStream<SoundPlan, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let reason = unavailability { throw reason }
                    if let locale, !supports(locale) { throw SoundDirectorError.unsupportedLanguage }
                    let prompt = try prompt(for: captions, videoDuration: videoDuration)

                    let session = LanguageModelSession(instructions: instructions)
                    let stream = session.streamResponse(
                        to: prompt,
                        generating: GeneratedPlan.self,
                        options: GenerationOptions(temperature: 0.4)
                    )
                    for try await snapshot in stream {
                        continuation.yield(SoundPlan(partial: snapshot.content).fitted(to: videoDuration))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : SoundDirectorError(error))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Prompt

    /// Characters of transcript sent to the model. About 1,500 tokens of English, which leaves room in the
    /// 4096-token window for the instructions and the answer.
    static let transcriptBudget = 6000

    static let instructions = """
        You are a sound designer for short videos. You get a timed transcript of what is said in a video.
        Suggest sound effects that make the scene feel real: weather, places, objects and actions that the \
        words mention or imply. A storm implies rain and thunder, coming home implies keys and a door, \
        a kitchen implies dishes. Start each effect at the second of the line that implies it.
        Never suggest speech, voices, singing, phones ringing or music as an effect unless the words name them.
        Short sounds last 1 to 4 seconds; ambience such as rain, wind or traffic lasts 6 to 15 seconds.
        Then suggest one prompt for instrumental background music that fits the mood: genre, instruments, tempo.
        Write every prompt in English, concrete and short, as you would search a sound library.
        """

    /// The request for one video: its length and its lines with their start times. Lines past the budget
    /// are left out, so a long video gets suggestions for its beginning instead of a context-window failure.
    static func prompt(for captions: [Caption], videoDuration: Double) throws(SoundDirectorError) -> String {
        let lines = captions
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
            .map { "\(seconds($0.start)) s: \($0.text)" }
        guard !lines.isEmpty else { throw .nothingToRead }

        var transcript = ""
        var cut = false
        for line in lines {
            guard transcript.count + line.count + 1 <= transcriptBudget else {
                cut = true
                break
            }

            transcript += line + "\n"
        }
        if transcript.isEmpty { throw .transcriptTooLong }

        let end = cut ? "\n(The transcript continues; plan only for the part above.)" : ""

        return "Video length: \(seconds(videoDuration)) s.\nTranscript:\n\(transcript)\(end)"
    }

    private static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

// MARK: - What the model fills in

/// Property order is generation order: the cue comes first so each effect is written from a line it quotes.
@Generable
struct GeneratedPlan {
    @Guide(description: "Sound effects for the video, in time order", .maximumCount(6))
    var effects: [GeneratedEffect]
    @Guide(description: "Prompt for instrumental background music: mood, genre, instruments, tempo")
    var musicPrompt: String
}

@Generable
struct GeneratedEffect {
    @Guide(description: "The words in the transcript that call for this sound, quoted")
    var cue: String
    @Guide(description: "Second in the video where the sound starts")
    var start: Double
    @Guide(description: "The sound itself, for example 'heavy rain against a window'")
    var prompt: String
    @Guide(description: "Length in seconds", .range(1...15))
    var duration: Double
}

extension SoundPlan {
    /// The plan as far as the model has written it. An effect counts once its start and some of its prompt
    /// are in; its length defaults until the model gets there.
    init(partial: GeneratedPlan.PartiallyGenerated) {
        let effects = (partial.effects ?? []).enumerated().compactMap { index, effect -> Effect? in
            guard let start = effect.start, let prompt = effect.prompt else { return nil }
            return Effect(id: index, start: start, duration: effect.duration ?? 2, prompt: prompt, cue: effect.cue ?? "")
        }

        self.init(effects: effects, musicPrompt: partial.musicPrompt ?? "")
    }
}
