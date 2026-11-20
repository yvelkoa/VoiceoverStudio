import Foundation
import Testing
import VoiceoverKit
@testable import VoiceoverStudio

/// The project owns its files: every removal has to take the media with it, and nothing may be left
/// pointing at a file that is gone.
struct ProjectTests {
    private let folder = TemporaryFolder()

    private func makeProject() -> Project {
        Project(folder: folder.url, title: "Test")
    }

    @Test func newProjectStartsWithOneActiveCharacter() {
        let project = makeProject()
        defer { folder.cleanUp() }

        #expect(project.characters.count == 1)
        #expect(project.activeCharacterID == project.characters.first?.id)
    }

    @Test func newCharacterTakesTheFirstUnusedColour() {
        let project = makeProject()
        defer { folder.cleanUp() }
        let second = project.addCharacter(named: "B")
        project.addCharacter(named: "C")

        project.removeCharacter(second.id)
        let replacement = project.addCharacter(named: "D")

        #expect(replacement.colorIndex == second.colorIndex)
        #expect(Set(project.characters.map(\.colorIndex)).count == project.characters.count)
    }

    @Test func removingACharacterRemovesItsTakesAndTheirFiles() throws {
        let project = makeProject()
        defer { folder.cleanUp() }
        let narrator = try #require(project.characters.first)
        let dog = project.addCharacter(named: "Dog")
        let kept = project.addTake(characterID: narrator.id, start: 0, duration: 2, recording: folder.file("a.m4a"))
        let dropped = project.addTake(characterID: dog.id, start: 3, duration: 2, recording: folder.file("b.m4a"))
        project.activeCharacterID = dog.id

        project.removeCharacter(dog.id)

        #expect(project.takes.map(\.id) == [kept.id])
        #expect(!exists(dropped.recording))
        #expect(exists(kept.recording))
        #expect(project.activeCharacterID == narrator.id)
    }

    @Test func theLastCharacterCannotBeRemoved() throws {
        let project = makeProject()
        defer { folder.cleanUp() }
        let only = try #require(project.characters.first)

        project.removeCharacter(only.id)

        #expect(project.characters.count == 1)
    }

    @Test func removingATakeRemovesItsTranscriptAndConversion() throws {
        let project = makeProject()
        defer { folder.cleanUp() }
        let narrator = try #require(project.characters.first)
        let take = project.addTake(characterID: narrator.id, start: 0, duration: 2, recording: folder.file("take.m4a"))
        let converted = folder.file("converted.m4a")
        project.setTranscript([TimedWord(text: "hi", start: 0, end: 0.5)], for: take.id)
        project.setConvertedAudio(converted, drift: 0.1, for: take.id)

        project.remove(take)

        #expect(project.transcripts[take.id] == nil)
        #expect(project.convertedAudio[take.id] == nil)
        #expect(project.conversionDrift[take.id] == nil)
        #expect(!exists(converted))
        #expect(!exists(take.recording))
    }

    @Test func aNewVoiceInvalidatesThatCharactersConversionsOnly() throws {
        let project = makeProject()
        defer { folder.cleanUp() }
        var narrator = try #require(project.characters.first)
        let dog = project.addCharacter(named: "Dog")
        let mine = project.addTake(characterID: narrator.id, start: 0, duration: 1, recording: folder.file("1.m4a"))
        let theirs = project.addTake(characterID: dog.id, start: 2, duration: 1, recording: folder.file("2.m4a"))
        project.setConvertedAudio(folder.file("1c.m4a"), drift: 0, for: mine.id)
        project.setConvertedAudio(folder.file("2c.m4a"), drift: 0, for: theirs.id)

        narrator.voice = Voice(voiceID: "v1", name: "Rachel")
        project.update(narrator)

        #expect(project.convertedAudio[mine.id] == nil)
        #expect(project.convertedAudio[theirs.id] != nil)
        #expect(project.takesNeedingConversion.map(\.id) == [mine.id])
        #expect(project.secondsNeedingConversion == 1)
    }

    @Test func renamingACharacterKeepsItsConversions() throws {
        let project = makeProject()
        defer { folder.cleanUp() }
        var narrator = try #require(project.characters.first)
        let take = project.addTake(characterID: narrator.id, start: 0, duration: 1, recording: folder.file("1.m4a"))
        project.setConvertedAudio(folder.file("1c.m4a"), drift: 0, for: take.id)

        narrator.name = "Host"
        project.update(narrator)

        #expect(project.convertedAudio[take.id] != nil)
    }

    @Test func resultsForAnUnknownTakeAreIgnored() {
        let project = makeProject()
        defer { folder.cleanUp() }
        let stranger = UUID()

        project.setTranscript([TimedWord(text: "late", start: 0, end: 1)], for: stranger)
        project.setConvertedAudio(folder.url, drift: 0, for: stranger)

        #expect(project.transcripts.isEmpty)
        #expect(project.convertedAudio.isEmpty)
    }

    @Test func effectsStayInsideTheVideo() {
        let project = makeProject()
        defer { folder.cleanUp() }
        project.setVideo(folder.file("video.mov"), duration: 10)
        let effect = SoundEffect(id: UUID(), prompt: "bark", start: 1, duration: 2, audio: folder.file("fx.mp3"))
        project.add(effect)

        project.move(effect, to: 20)
        #expect(project.effects.first?.start == 8)

        project.move(effect, to: -5)
        #expect(project.effects.first?.start == 0)
    }

    @Test func aNewVideoDropsEverythingRecordedForTheOldOne() throws {
        let project = makeProject()
        defer { folder.cleanUp() }
        let oldVideo = folder.file("old.mov")
        project.setVideo(oldVideo, duration: 10)
        let narrator = try #require(project.characters.first)
        let take = project.addTake(characterID: narrator.id, start: 0, duration: 1, recording: folder.file("t.m4a"))
        let effect = SoundEffect(id: UUID(), prompt: "boom", start: 0, duration: 1, audio: folder.file("fx.mp3"))
        project.add(effect)
        project.trimStart = 2
        project.exportedURL = folder.file("export.mp4")

        project.setVideo(folder.file("new.mov"), duration: 5)

        #expect(project.takes.isEmpty)
        #expect(project.effects.isEmpty)
        #expect(!project.isTrimmed)
        #expect(project.exportedURL == nil)
        #expect(!exists(oldVideo))
        #expect(!exists(take.recording))
        #expect(!exists(effect.audio))
        #expect(project.videoDuration == 5)
    }

    @Test func trimRangeNeverCollapses() {
        let project = makeProject()
        defer { folder.cleanUp() }
        project.setVideo(folder.file("video.mov"), duration: 10)

        #expect(project.trimRange == 0...10)
        project.trimStart = 4
        project.trimEnd = 4
        #expect(project.trimRange.upperBound > project.trimRange.lowerBound)
    }

    @Test func documentRoundTripKeepsTheEdit() throws {
        let project = makeProject()
        defer { folder.cleanUp() }
        project.setVideo(folder.file("video.mov"), duration: 12)
        let narrator = try #require(project.characters.first)
        let take = project.addTake(characterID: narrator.id, start: 1, duration: 2, recording: folder.file("t.m4a"))
        project.setTranscript([TimedWord(text: "hello", start: 0, end: 0.4)], for: take.id)
        project.setConvertedAudio(folder.file("c.m4a"), drift: 0.3, for: take.id)
        project.add(SoundEffect(id: UUID(), prompt: "rain", start: 3, duration: 4, audio: folder.file("fx.mp3")))
        project.mix.voice = 0.4
        project.trimEnd = 9
        project.mode = .type
        project.script = "Hi there"

        let restored = Project(document: project.document, folder: folder.url)

        #expect(try encoded(restored.document) == encoded(project.document))
        #expect(restored.takes.first?.recording == take.recording)
        #expect(restored.convertedAudio[take.id] == project.convertedAudio[take.id])
    }

    private func encoded(_ document: ProjectDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        return try encoder.encode(document)
    }
}
