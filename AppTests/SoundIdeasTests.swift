import Foundation
import Testing
import VoiceoverKit
@testable import VoiceoverStudio

/// Suggested sounds: the plan streams in from a stubbed director, and the picked effects are generated
/// against a stubbed ElevenLabs.
struct SoundIdeasTests {
    private let folder = TemporaryFolder()

    private func makeModel(services: EditorServices, transport: StubTransport? = nil) -> EditorModel {
        let project = Project(folder: folder.url, title: "Test")
        project.setVideo(folder.file("video.mov"), duration: 12)
        let client = transport.map { ElevenLabsClient(transport: $0, apiKey: { "key" }) } ?? ElevenLabsClient(apiKey: { nil })

        return EditorModel(project: project, client: client, store: nil, services: services)
    }

    private let rain = SoundPlan.Effect(id: 0, start: 3, duration: 6, prompt: "rain on a window", cue: "this storm")
    private let door = SoundPlan.Effect(id: 1, start: 0.5, duration: 2, prompt: "front door closes", cue: "I'm home")

    @Test func thePlanFillsInAsItStreamsAndReadsTheCaptionsInTheRecordingLanguage() async throws {
        defer { folder.cleanUp() }
        let requests = Recorder<([Caption], Double, Locale?)>()
        let partial = SoundPlan(effects: [rain])
        let final = SoundPlan(effects: [door, rain], musicPrompt: "slow ambient piano")
        var services = EditorServices.stub()
        services.recordingLocale = { Locale(identifier: "en-GB") }
        services.planSounds = { captions, duration, locale in
            requests.append((captions, duration, locale))
            return AsyncThrowingStream { continuation in
                continuation.yield(partial)
                continuation.yield(final)
                continuation.finish()
            }
        }

        let model = makeModel(services: services)
        let captions = [Caption(id: 0, text: "I'm home.", start: 0, end: 1)]
        model.captions = captions

        model.suggestSounds()

        #expect(model.soundIdeas.isPlanning)
        #expect(await eventually { !model.soundIdeas.isPlanning })
        #expect(model.soundIdeas.plan == final)
        #expect(model.soundIdeas.failure == nil)
        let request = try #require(requests.values.first)
        #expect(request.0 == captions)
        #expect(request.1 == 12)
        #expect(request.2?.identifier == "en-GB")
    }

    /// A director that writes `plans` and then never finishes, the way the model sometimes does.
    private func stalling(after plans: [SoundPlan]) -> EditorServices {
        var services = EditorServices.stub()
        services.planSounds = { _, _, _ in
            AsyncThrowingStream { continuation in
                for plan in plans { continuation.yield(plan) }
            }
        }

        return services
    }

    @Test func aPlanThatNeverFinishesKeepsWhatItHasWhenTimeRunsOut() async {
        let partial = SoundPlan(effects: [rain])
        let ideas = SoundIdeas(services: stalling(after: [partial]), timeLimit: .milliseconds(100))

        ideas.suggest(from: [], videoDuration: 12, locale: nil)

        #expect(await eventually { !ideas.isPlanning })
        #expect(ideas.plan == partial)
        #expect(ideas.failure == nil, "effects without a music prompt are still worth picking from")
    }

    @Test func aPlanThatNeverStartsFailsWhenTimeRunsOut() async {
        let ideas = SoundIdeas(services: stalling(after: []), timeLimit: .milliseconds(100))

        ideas.suggest(from: [], videoDuration: 12, locale: nil)

        #expect(await eventually { !ideas.isPlanning })
        #expect(ideas.plan == nil)
        #expect(ideas.failure != nil)
    }

    @Test func runningOutOfTimeStopsTheDirector() async {
        let stopped = Recorder<Bool>()
        var services = EditorServices.stub()
        services.planSounds = { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in stopped.append(true) }
            }
        }
        let ideas = SoundIdeas(services: services, timeLimit: .milliseconds(100))

        ideas.suggest(from: [], videoDuration: 12, locale: nil)

        #expect(await eventually { !stopped.values.isEmpty })
    }

    @Test func askingAgainMidPlanLeavesOnlyTheNewPlan() async {
        defer { folder.cleanUp() }
        let gate = Gate()
        let calls = Recorder<Int>()
        let final = SoundPlan(effects: [rain], musicPrompt: "slow ambient piano")
        var services = EditorServices.stub()
        services.planSounds = { _, _, _ in
            calls.append(calls.count)
            let isFirst = calls.count == 1

            return AsyncThrowingStream { continuation in
                let task = Task { @MainActor in
                    // The first plan never finishes on its own; it is superseded.
                    if isFirst { await gate.wait() }
                    continuation.yield(final)
                    continuation.finish()
                }

                continuation.onTermination = { _ in task.cancel() }
            }
        }

        let model = makeModel(services: services)

        model.suggestSounds()
        #expect(await eventually { gate.isWaiting })
        model.suggestSounds()

        #expect(await eventually { !model.soundIdeas.isPlanning })
        gate.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.soundIdeas.plan == final)
        #expect(model.soundIdeas.failure == nil, "the superseded run must not report an empty plan")
        #expect(!model.soundIdeas.isPlanning)
    }

    @Test func aTypedScriptIsNotCheckedAgainstTheRecordingLanguage() async {
        defer { folder.cleanUp() }
        let locales = Recorder<Locale?>()
        var services = EditorServices.stub()
        services.planSounds = { _, _, locale in
            locales.append(locale)
            return AsyncThrowingStream { $0.finish() }
        }

        let model = makeModel(services: services)
        model.mode = .type

        model.suggestSounds()

        #expect(await eventually { locales.count == 1 })
        #expect(locales.values == [nil])
    }

    @Test func aFailureIsShownInTheSheetNotAsAnEditorAlert() async {
        defer { folder.cleanUp() }
        var services = EditorServices.stub()
        services.planSounds = { _, _, _ in
            AsyncThrowingStream { $0.finish(throwing: SoundDirectorError.unsupportedLanguage) }
        }

        let model = makeModel(services: services)

        model.suggestSounds()

        #expect(await eventually { !model.soundIdeas.isPlanning })
        #expect(model.soundIdeas.failure == SoundDirectorError.unsupportedLanguage.localizedDescription)
        #expect(model.failure == nil)
    }

    @Test func pickedEffectsLandWhereThePlanPutThemAndARetrySkipsTheOnesAlreadyIn() async throws {
        defer { folder.cleanUp() }
        let edits = Recorder<[AudioClip]>()
        var services = EditorServices.stub(duration: 2)
        services.compose = { _, clips in
            edits.append(clips)
            return EditorServices.emptyEdit()
        }

        // The first effect is generated, the second fails, then succeeds on the retry.
        let transport = StubTransport([(200, Data("ID3".utf8)), (500, Data()), (200, Data("ID3".utf8))])
        let model = makeModel(services: services, transport: transport)
        #expect(await eventually { model.activity == nil && edits.count == 1 })

        model.addEffects([door, rain])

        #expect(await eventually { model.failure != nil && model.activity == nil })
        #expect(model.project.effects.map(\.prompt) == ["front door closes"])
        #expect(model.project.effects.first?.start == 0.5)
        #expect(await eventually { edits.values.last?.contains { $0.kind == .effect } == true },
                "the effect that made it in is heard")

        let retry = try #require(model.failure?.retry)
        model.failure = nil
        retry()

        #expect(await eventually { model.project.effects.count == 2 && model.activity == nil })
        let prompts = transport.requests.compactMap { request -> String? in
            let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            return body?["text"] as? String
        }
        #expect(prompts == ["front door closes", "rain on a window", "rain on a window"])
        #expect(model.project.effects.map(\.start).sorted() == [0.5, 3])
    }
}
