import Foundation
import Testing
@testable import VoiceoverKit

/// The parts of the sound director that don't need the model: the request it sends and how its answer is
/// made safe to act on.
struct SoundDirectorTests {

    // MARK: - Fitting a plan to the video

    @Test func effectsArePulledInsideTheVideoAndIntoLengthsTheAPIAccepts() {
        let plan = SoundPlan(effects: [
            .init(id: 0, start: -3, duration: 0.1, prompt: "door slam"),
            .init(id: 1, start: 30, duration: 4, prompt: "thunder"),
            .init(id: 2, start: 8, duration: 60, prompt: "rain"),
        ])

        let fitted = plan.fitted(to: 10)

        #expect(fitted.effects.map(\.start) == [0, 8, 9.5])
        #expect(fitted.effects.map(\.duration) == [0.5, 2, 0.5], "never past the end, never under the API's minimum")
        #expect(fitted.effects.map(\.prompt) == ["door slam", "rain", "thunder"])
        #expect(fitted.effects.map(\.id) == [0, 1, 2], "renumbered in time order")
    }

    @Test func blankAndRepeatedPromptsAreDropped() {
        let plan = SoundPlan(effects: [
            .init(id: 0, start: 1, duration: 2, prompt: "  Rain "),
            .init(id: 1, start: 2, duration: 2, prompt: "   "),
            .init(id: 2, start: 3, duration: 2, prompt: "rain"),
            .init(id: 3, start: .nan, duration: 2, prompt: "wind"),
        ], musicPrompt: "  soft piano \n")

        let fitted = plan.fitted(to: 10)

        #expect(fitted.effects.map(\.prompt) == ["Rain"])
        #expect(fitted.musicPrompt == "soft piano")
    }

    @Test func aPlanKeepsAtMostTheMaximumNumberOfEffects() {
        let effects = (0..<10).map { SoundPlan.Effect(id: $0, start: Double($0), duration: 1, prompt: "sound \($0)") }

        let fitted = SoundPlan(effects: effects).fitted(to: 20)

        #expect(fitted.effects.count == SoundPlan.maximumEffects)
        #expect(fitted.effects.first?.prompt == "sound 0", "the first ones the model wrote")
    }

    // MARK: - The request

    @Test func theRequestListsEachLineWithItsStartInTimeOrder() throws {
        let captions = [
            Caption(id: 1, text: "Who left the window open?", start: 3, end: 5),
            Caption(id: 0, text: "I'm home.", start: 0.34, end: 2),
            Caption(id: 2, text: "  ", start: 6, end: 7),
        ]

        let prompt = try SoundDirector.prompt(for: captions, videoDuration: 12)

        #expect(prompt == "Video length: 12.0 s.\nTranscript:\n0.3 s: I'm home.\n3.0 s: Who left the window open?\n")
    }

    @Test func aLongTranscriptIsCutAndTheModelIsTold() throws {
        let line = String(repeating: "word ", count: 40)
        let captions = (0..<100).map { Caption(id: $0, text: line, start: Double($0), end: Double($0) + 1) }

        let prompt = try SoundDirector.prompt(for: captions, videoDuration: 100)

        #expect(prompt.count < SoundDirector.transcriptBudget + 200)
        #expect(prompt.hasSuffix("plan only for the part above.)"))
    }

    @Test func withoutWordsThereIsNothingToPlan() {
        #expect(throws: SoundDirectorError.nothingToRead) {
            try SoundDirector.prompt(for: [], videoDuration: 10)
        }
    }

    // MARK: - Errors

    @Test func everyErrorHasAMessage() {
        let errors: [SoundDirectorError] = [
            .deviceNotEligible, .appleIntelligenceOff, .modelNotReady, .unsupportedLanguage, .nothingToRead,
            .transcriptTooLong, .declined, .failed("x"),
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }

    @Test func foreignErrorsKeepTheirDescription() {
        #expect(SoundDirectorError(StubError()) == .failed("stub"))
        #expect(SoundDirectorError(SoundDirectorError.declined) == .declined)
    }
}

private struct StubError: LocalizedError {
    var errorDescription: String? { "stub" }
}

/// Runs the real on-device model. Skipped where Apple Intelligence isn't on (CI runners, most Macs);
/// on a Mac that has it, this is the quickest way to see what the prompt produces.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil && SoundDirector.unavailability == nil))
struct SoundDirectorLiveTests {
    @Test(.timeLimit(.minutes(1))) func aStormyHomecomingGetsWeatherAndHouseSounds() async throws {
        let captions = [
            Caption(id: 0, text: "Okay, I'm finally home.", start: 0, end: 2.5),
            Caption(id: 1, text: "Who left the window open in this storm?", start: 3, end: 5),
            Caption(id: 2, text: "Wait... is someone in the kitchen?", start: 6, end: 8.5),
            Caption(id: 3, text: "Hello? Hello?!", start: 9, end: 11),
        ]
        let clock = ContinuousClock()
        let started = clock.now
        var plans: [SoundPlan] = []

        for try await plan in SoundDirector.plan(for: captions, videoDuration: 12, locale: Locale(identifier: "en-US")) {
            plans.append(plan)
        }

        let plan = try #require(plans.last)
        print("plan in \(clock.now - started), \(plans.count) snapshots")
        for effect in plan.effects {
            print("  \(effect.start) s, \(effect.duration) s: \(effect.prompt)  ← \(effect.cue)")
        }

        print("  music: \(plan.musicPrompt)")
        #expect(!plan.effects.isEmpty)
        #expect(!plan.musicPrompt.isEmpty)
        #expect(plan.effects.allSatisfy { $0.start >= 0 && $0.start + $0.duration <= 12 })
    }

    @Test func russianIsReportedAsUnsupported() async {
        let captions = [Caption(id: 0, text: "Я наконец-то дома.", start: 0, end: 2)]
        await #expect(throws: SoundDirectorError.unsupportedLanguage) {
            for try await _ in SoundDirector.plan(for: captions, videoDuration: 5, locale: Locale(identifier: "ru-RU")) {}
        }
    }
}
