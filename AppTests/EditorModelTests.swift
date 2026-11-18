import Foundation
import Testing
import VoiceoverKit
@testable import VoiceoverStudio

/// Edits that go through the model rather than straight to the project. No video is loaded, so nothing
/// is composed and no media framework is involved.
struct EditorModelTests {
    private let folder = TemporaryFolder()

    private func makeModel() -> EditorModel {
        let project = Project(folder: folder.url, title: "Test")
        return EditorModel(project: project, client: ElevenLabsClient(apiKey: { nil }), store: nil)
    }

    @Test func trimEndBeforeStartClearsTheStaleEnd() {
        defer { folder.cleanUp() }
        let model = makeModel()

        model.setTrim(end: 3)
        model.setTrim(start: 5)

        #expect(model.project.trimStart == 5)
        #expect(model.project.trimEnd == nil)

        model.setTrim(clear: true)
        #expect(!model.project.isTrimmed)
    }

    @Test func trimDropsTheExportThatNoLongerMatches() {
        defer { folder.cleanUp() }
        let model = makeModel()
        let export = folder.file("export.mp4")
        model.project.exportedURL = export
        model.savedToPhotos = true

        model.setTrim(start: 1)

        #expect(model.project.exportedURL == nil)
        #expect(!exists(export))
        #expect(!model.savedToPhotos)
    }

    @Test func switchingModeShowsThatModesCaptions() {
        defer { folder.cleanUp() }
        let model = makeModel()
        let typed = [Caption(id: 0, text: "Typed", start: 0, end: 1)]
        model.project.typeCaptions = typed

        model.mode = .type
        #expect(model.captions == typed)

        model.mode = .record
        #expect(model.captions.isEmpty)
    }

    @Test func transcriptArrivingForATakeBecomesACaption() throws {
        defer { folder.cleanUp() }
        let model = makeModel()
        let narrator = try #require(model.project.characters.first)
        let take = model.project.addTake(characterID: narrator.id, start: 2, duration: 1, recording: folder.file("t.m4a"))

        model.transcriptions.onWords?(take.id, [TimedWord(text: "hello", start: 0, end: 0.5)])

        #expect(model.captions.map(\.text).joined(separator: " ").contains("hello"))
    }

    @Test func deletingATakeRemovesItsCaption() throws {
        defer { folder.cleanUp() }
        let model = makeModel()
        let narrator = try #require(model.project.characters.first)
        let take = model.project.addTake(characterID: narrator.id, start: 0, duration: 1, recording: folder.file("t.m4a"))
        model.transcriptions.onWords?(take.id, [TimedWord(text: "gone", start: 0, end: 0.5)])

        model.delete(take)

        #expect(model.project.takes.isEmpty)
        #expect(model.captions.isEmpty)
    }

    @Test func swapNeedsAVoiceForEveryCharacterWithTakes() throws {
        defer { folder.cleanUp() }
        let model = makeModel()
        let narrator = try #require(model.project.characters.first)
        model.project.setVideo(folder.file("video.mov"), duration: 10)
        model.project.addTake(characterID: narrator.id, start: 0, duration: 1, recording: folder.file("t.m4a"))

        model.swapVoices()

        #expect(model.failure?.recovery == .editInput)
        #expect(!model.isBusy)
    }

    @Test func aStoredRetryDoesNotKeepTheModelAlive() {
        defer { folder.cleanUp() }
        weak var released: EditorModel?

        do {
            let model = makeModel()
            model.failure = .init(message: "x", recovery: .retry) { [weak model] in model?.recompose() }
            model.transcriptions.onFailure?(
                Take(characterID: UUID(), start: 0, duration: 1, recording: folder.url, sequence: 1), CancellationError()
            )
            released = model
        }

        #expect(released == nil)
    }
}
