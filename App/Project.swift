import Foundation
import Observation
import VoiceoverKit

/// The edit itself: the video, who speaks in it and what was recorded. No networking, no AVFoundation.
@Observable
final class Project {
    private(set) var videoURL: URL?
    private(set) var videoDuration: Double = 0

    private(set) var characters: [Character] = []
    var activeCharacterID: Character.ID?
    private(set) var takes: [Take] = []

    /// Words recognised in each take, with times relative to the take's start.
    private(set) var transcripts: [Take.ID: [TimedWord]] = [:]
    /// The same take spoken by the character's ElevenLabs voice.
    private(set) var convertedAudio: [Take.ID: URL] = [:]

    var effectPrompt = ""
    var effectStart: Double = 0

    private var nextSequence = 0

    init() {
        addCharacter(named: "Narrator")
    }

    var activeCharacter: Character? {
        characters.first { $0.id == activeCharacterID }
    }

    /// The audible slices after overlap resolution, in timeline order.
    var segments: [AudioSegment] { TakeResolver.segments(for: takes) }

    func character(_ id: Character.ID) -> Character? {
        characters.first { $0.id == id }
    }

    // MARK: - Video

    func setVideo(_ url: URL, duration: Double) {
        videoURL = url
        videoDuration = duration
        effectStart = min(effectStart, duration)
        takes.removeAll()
        transcripts.removeAll()
        convertedAudio.removeAll()
    }

    // MARK: - Characters

    @discardableResult
    func addCharacter(named name: String) -> Character {
        let character = Character(name: name, colorIndex: characters.count)
        characters.append(character)
        if activeCharacterID == nil { activeCharacterID = character.id }
        return character
    }

    func update(_ character: Character) {
        guard let index = characters.firstIndex(where: { $0.id == character.id }) else { return }
        let voiceChanged = characters[index].voice != character.voice
        let settingsChanged = characters[index].settings != character.settings
        characters[index] = character
        if voiceChanged || settingsChanged {
            // The converted audio was made with the old voice; it has to be redone.
            for take in takes where take.characterID == character.id {
                convertedAudio[take.id] = nil
            }
        }
    }

    func removeCharacter(_ id: Character.ID) {
        guard characters.count > 1 else { return }
        characters.removeAll { $0.id == id }
        for take in takes where take.characterID == id { remove(take) }
        if activeCharacterID == id { activeCharacterID = characters.first?.id }
    }

    // MARK: - Takes

    @discardableResult
    func addTake(characterID: Character.ID, start: Double, duration: Double, recording: URL) -> Take {
        nextSequence += 1
        let take = Take(characterID: characterID, start: start, duration: duration, recording: recording, sequence: nextSequence)
        takes.append(take)
        return take
    }

    func remove(_ take: Take) {
        takes.removeAll { $0.id == take.id }
        transcripts[take.id] = nil
        convertedAudio[take.id] = nil
        try? FileManager.default.removeItem(at: take.recording)
    }

    func setTranscript(_ words: [TimedWord], for takeID: Take.ID) {
        guard takes.contains(where: { $0.id == takeID }) else { return }
        transcripts[takeID] = words
    }

    func setConvertedAudio(_ url: URL, for takeID: Take.ID) {
        guard takes.contains(where: { $0.id == takeID }) else { return }
        convertedAudio[takeID] = url
    }

    /// Takes whose converted audio is missing or stale.
    var takesNeedingConversion: [Take] {
        takes.filter { convertedAudio[$0.id] == nil }
    }

    /// Total seconds that a voice swap would send to ElevenLabs; the API bills by audio length.
    var secondsNeedingConversion: Double {
        takesNeedingConversion.reduce(0) { $0 + $1.duration }
    }
}
