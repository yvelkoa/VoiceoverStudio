import Foundation
import Testing
import VoiceoverKit
@testable import VoiceoverStudio

/// The credit- and minute-spending steps, run against stub services: no media, no Photos, no network.
struct EditorJobsTests {
    private let folder = TemporaryFolder()

    /// A project with a 20 s video and one take, so there is something to compose and export.
    private func makeProject() throws -> Project {
        let project = Project(folder: folder.url, title: "Test")
        project.setVideo(folder.file("video.mov"), duration: 20)
        let narrator = try #require(project.characters.first)
        project.addTake(characterID: narrator.id, start: 1, duration: 2, recording: folder.file("take.m4a"))

        return project
    }

    @Test func retryAfterAFailedPhotosSaveSavesAgainWithoutReExporting() async throws {
        defer { folder.cleanUp() }
        let exports = Recorder<URL>()
        let saves = Recorder<URL>()
        var services = EditorServices.stub()
        let export = services.export
        services.export = { composed, captions, levels, range, output in
            exports.append(output)
            return try await export(composed, captions, levels, range, output)
        }

        services.saveToPhotos = { url in
            saves.append(url)
            if saves.count == 1 { throw StubFailure() }
        }

        let model = EditorModel(
            project: try makeProject(), client: ElevenLabsClient(apiKey: { nil }), store: nil, services: services
        )
        #expect(await eventually { model.composed != nil && model.activity == nil })

        model.export()
        #expect(await eventually { model.failure != nil })
        #expect(exports.count == 1)

        let retry = try #require(model.failure?.retry)
        model.failure = nil
        retry()

        #expect(await eventually { model.savedToPhotos })
        #expect(exports.count == 1, "the video was already rendered; only the save is repeated")
        #expect(saves.values == [exports.values[0], exports.values[0]])
    }

    @Test func retryAfterAFailedRenderRendersAgain() async throws {
        defer { folder.cleanUp() }
        let exports = Recorder<URL>()
        var services = EditorServices.stub()
        let export = services.export
        services.export = { composed, captions, levels, range, output in
            exports.append(output)
            if exports.count == 1 { throw StubFailure() }

            return try await export(composed, captions, levels, range, output)
        }

        let model = EditorModel(
            project: try makeProject(), client: ElevenLabsClient(apiKey: { nil }), store: nil, services: services
        )
        #expect(await eventually { model.composed != nil && model.activity == nil })

        model.export()
        #expect(await eventually { model.failure != nil })
        let retry = try #require(model.failure?.retry)
        model.failure = nil
        retry()

        #expect(await eventually { model.savedToPhotos })
        #expect(exports.count == 2)
    }

    @Test func openingAProjectKeepsItsExport() async throws {
        defer { folder.cleanUp() }
        let project = try makeProject()
        let export = folder.file("export.mp4")
        project.exportedURL = export

        let model = EditorModel(project: project, client: ElevenLabsClient(apiKey: { nil }), store: nil, services: .stub())
        #expect(await eventually { model.composed != nil && model.activity == nil })

        #expect(project.exportedURL == export, "rebuilding the player on open is not an edit")
        #expect(exists(export))
    }

    @Test func anExportWhoseFileIsGoneIsForgottenOnOpen() async throws {
        defer { folder.cleanUp() }
        let project = try makeProject()
        project.exportedURL = folder.url.appending(path: "missing.mp4")

        let model = EditorModel(project: project, client: ElevenLabsClient(apiKey: { nil }), store: nil, services: .stub())

        #expect(model.exportedURL == nil)
    }

    @Test func rendersLeftByAKilledExportAreSweptOnOpen() async throws {
        defer { folder.cleanUp() }
        let project = try makeProject()
        let kept = project.fileURL(Project.exportPrefix, extension: "mp4")
        let stray = project.fileURL(Project.exportPrefix, extension: "mp4")
        try Data("kept".utf8).write(to: kept)
        try Data("stray".utf8).write(to: stray)
        project.exportedURL = kept

        _ = EditorModel(project: project, client: ElevenLabsClient(apiKey: { nil }), store: nil, services: .stub())

        #expect(exists(kept))
        #expect(!exists(stray))
    }

    @Test func changingTheMixDropsTheExportRenderedAtTheOldLevels() async throws {
        defer { folder.cleanUp() }
        let project = try makeProject()
        let model = EditorModel(project: project, client: ElevenLabsClient(apiKey: { nil }), store: nil, services: .stub())
        #expect(await eventually { model.composed != nil && model.activity == nil })
        model.export()
        #expect(await eventually { model.savedToPhotos })
        let export = try #require(project.exportedURL)

        project.mix.voice = 0.5
        model.applyMix()

        #expect(project.exportedURL == nil)
        #expect(!exists(export))
        #expect(!model.savedToPhotos)
    }

    @Test func aFailedRenderLeavesNoPartialFile() async throws {
        defer { folder.cleanUp() }
        let outputs = Recorder<URL>()
        var services = EditorServices.stub()
        services.export = { _, _, _, _, output in
            outputs.append(output)
            FileManager.default.createFile(atPath: output.path, contents: Data([0]))
            throw StubFailure()
        }

        let model = EditorModel(
            project: try makeProject(), client: ElevenLabsClient(apiKey: { nil }), store: nil, services: services
        )
        #expect(await eventually { model.composed != nil && model.activity == nil })

        model.export()

        #expect(await eventually { model.failure != nil })
        let output = try #require(outputs.values.first)
        #expect(!exists(output))
    }

    @Test func aRetriedTranscriptionCanStillBeCancelled() async throws {
        defer { folder.cleanUp() }
        let gate = Gate()
        let started = Recorder<Int>()
        var services = EditorServices.stub()
        services.transcribe = { _, _ in
            started.append(1)
            await gate.wait()
            try Task.checkCancellation()

            return [TimedWord(text: "late", start: 0, end: 0.2)]
        }

        let take = try #require(try makeProject().takes.first)
        let queue = TranscriptionQueue(services: services)
        var delivered = false
        queue.onWords = { _, _ in delivered = true }

        queue.transcribe(take)
        queue.transcribe(take)
        #expect(await eventually { started.count == 2 })
        // Let the superseded task unwind; it must not take the newer task's entry with it.
        try await Task.sleep(for: .milliseconds(50))
        queue.cancel(take.id)
        gate.open()
        try await Task.sleep(for: .milliseconds(100))

        #expect(!delivered, "the take was deleted; its words must not arrive")
    }

    @Test func musicIsComposedForTheExportRangeAndFollowsItsStart() async throws {
        defer { folder.cleanUp() }
        let project = try makeProject()
        project.trimStart = 4
        project.trimEnd = 14
        let edits = Recorder<[AudioClip]>()
        var services = EditorServices.stub(duration: 10)
        services.compose = { _, clips in
            edits.append(clips)
            return EditorServices.emptyEdit()
        }

        let transport = StubTransport([(200, Data("ID3".utf8))])
        let client = ElevenLabsClient(transport: transport, apiKey: { "key" })
        let model = EditorModel(project: project, client: client, store: nil, services: services)
        #expect(await eventually { model.activity == nil && edits.count == 1 })
        #expect(model.musicLength == 10)

        model.generateMusic(prompt: "calm piano")

        #expect(await eventually { project.music != nil && model.activity == nil })
        let body = try JSONSerialization.jsonObject(with: transport.requests.first?.httpBody ?? Data()) as? [String: Any]
        #expect(body?["music_length_ms"] as? Int == 10_000, "ten seconds of export, not twenty of video")
        #expect(edits.values.last?.first { $0.kind == .music }?.start == 4)

        model.setTrim(start: 6)

        #expect(await eventually { edits.values.last?.first { $0.kind == .music }?.start == 6 })
    }

    @Test func withoutATrimMusicSpansTheVideo() throws {
        defer { folder.cleanUp() }
        let model = EditorModel(
            project: try makeProject(), client: ElevenLabsClient(apiKey: { nil }), store: nil, services: .stub()
        )

        #expect(model.musicLength == 20)
    }

    @Test func transcriptionUsesTheRecordingLanguageAtTheTimeOfTheTake() async throws {
        defer { folder.cleanUp() }
        let locales = Recorder<Locale>()
        var services = EditorServices.stub()
        services.recordingLocale = { Locale(identifier: "uk-UA") }
        services.transcribe = { _, locale in
            locales.append(locale)
            return [TimedWord(text: "привіт", start: 0, end: 0.4)]
        }

        let project = try makeProject()
        let take = try #require(project.takes.first)
        let queue = TranscriptionQueue(services: services)
        var words: [TimedWord] = []
        queue.onWords = { _, result in words = result }

        queue.transcribe(take)

        #expect(await eventually { !words.isEmpty })
        #expect(locales.values == [Locale(identifier: "uk-UA")])
    }
}
