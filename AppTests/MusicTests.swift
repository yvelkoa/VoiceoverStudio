import Foundation
import Testing
@testable import VoiceoverStudio

/// Background music is one file per project: replacing or dropping it must take the old file with it.
struct MusicTests {
    private let folder = TemporaryFolder()

    @Test func newMusicReplacesTheOldTrackAndItsFile() {
        let project = Project(folder: folder.url, title: "Test")
        defer { folder.cleanUp() }
        let first = BackgroundMusic(prompt: "piano", duration: 10, audio: folder.file("music-a.mp3"))
        let second = BackgroundMusic(prompt: "drums", duration: 10, audio: folder.file("music-b.mp3"))

        project.setMusic(first)
        project.setMusic(second)

        #expect(project.music == second)
        #expect(!exists(first.audio))
        #expect(exists(second.audio))
    }

    @Test func removingMusicDeletesItsFile() {
        let project = Project(folder: folder.url, title: "Test")
        defer { folder.cleanUp() }
        let music = BackgroundMusic(prompt: "piano", duration: 10, audio: folder.file("music.mp3"))
        project.setMusic(music)

        project.removeMusic()

        #expect(project.music == nil)
        #expect(!exists(music.audio))
    }

    @Test func aNewVideoDropsTheMusicComposedForTheOldOne() {
        let project = Project(folder: folder.url, title: "Test")
        defer { folder.cleanUp() }
        let music = BackgroundMusic(prompt: "piano", duration: 10, audio: folder.file("music.mp3"))
        project.setMusic(music)

        project.setVideo(folder.file("video.mov"), duration: 20)

        #expect(project.music == nil)
        #expect(!exists(music.audio))
    }

    @Test func musicSurvivesSaveAndLoad() throws {
        let project = Project(folder: folder.url, title: "Test")
        defer { folder.cleanUp() }
        let music = BackgroundMusic(prompt: "piano", duration: 12.5, audio: folder.file("music.mp3"))
        project.setMusic(music)
        project.mix.music = 0.6

        let data = try JSONEncoder().encode(project.document)
        let loaded = Project(document: try JSONDecoder().decode(ProjectDocument.self, from: data), folder: folder.url)

        #expect(loaded.music == music)
        #expect(loaded.mix.music == 0.6)
    }

    @Test func aMixSavedBeforeMusicKeepsItsLevels() throws {
        let json = Data(#"{"original": 0.1, "voice": 0.9, "effect": 0.5}"#.utf8)

        let mix = try JSONDecoder().decode(MixLevels.self, from: json)

        #expect(mix.original == 0.1)
        #expect(mix.voice == 0.9)
        #expect(mix.effect == 0.5)
        #expect(mix.music == MixLevels().music)
    }
}
