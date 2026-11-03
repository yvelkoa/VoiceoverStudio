import Foundation
import Observation
import VoiceoverKit

/// A generated sound placed on the timeline. Generated once, kept on disk; moving it never calls the API.
struct SoundEffect: Identifiable, Equatable, Sendable {
    let id: UUID
    var prompt: String
    var start: Double
    let duration: Double
    let audio: URL

    var end: Double { start + duration }
}

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
    /// Seconds the converted audio is longer (or shorter) than the recording. Large values desync captions.
    private(set) var conversionDrift: [Take.ID: Double] = [:]
    /// Peak levels of each recording, for the timeline.
    private(set) var waveforms: [Take.ID: Waveform] = [:]

    private(set) var effects: [SoundEffect] = []

    /// Mix levels, 0...1. Used by the preview and the export alike.
    var mix = MixLevels()

    /// Export range in seconds; nil ends mean the video's own start or end.
    var trimStart: Double?
    var trimEnd: Double?

    var trimRange: ClosedRange<Double> {
        let start = trimStart ?? 0
        let end = trimEnd ?? videoDuration
        return start...max(end, start + 0.1)
    }

    var isTrimmed: Bool { trimStart != nil || trimEnd != nil }

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
        trimStart = nil
        trimEnd = nil
        for effect in effects { try? FileManager.default.removeItem(at: effect.audio) }
        effects.removeAll()
        takes.removeAll()
        transcripts.removeAll()
        convertedAudio.removeAll()
        conversionDrift.removeAll()
        waveforms.removeAll()
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
                conversionDrift[take.id] = nil
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
        conversionDrift[take.id] = nil
        waveforms[take.id] = nil
        try? FileManager.default.removeItem(at: take.recording)
    }

    func setWaveform(_ waveform: Waveform, for takeID: Take.ID) {
        guard takes.contains(where: { $0.id == takeID }) else { return }
        waveforms[takeID] = waveform
    }

    func setTranscript(_ words: [TimedWord], for takeID: Take.ID) {
        guard takes.contains(where: { $0.id == takeID }) else { return }
        transcripts[takeID] = words
    }

    func setConvertedAudio(_ url: URL, drift: Double, for takeID: Take.ID) {
        guard takes.contains(where: { $0.id == takeID }) else { return }
        convertedAudio[takeID] = url
        conversionDrift[takeID] = drift
    }

    /// Characters that have takes but no voice yet; a swap can't start until they do.
    var charactersMissingVoice: [Character] {
        characters.filter { character in
            character.voice == nil && takes.contains { $0.characterID == character.id }
        }
    }

    // MARK: - Effects

    func add(_ effect: SoundEffect) {
        effects.append(effect)
    }

    func remove(_ effect: SoundEffect) {
        effects.removeAll { $0.id == effect.id }
        waveforms[effect.id] = nil
        try? FileManager.default.removeItem(at: effect.audio)
    }

    func move(_ effect: SoundEffect, to start: Double) {
        guard let index = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        effects[index].start = min(max(start, 0), max(videoDuration - effect.duration, 0))
    }

    /// Waveforms are keyed by take or effect id alike.
    func setWaveform(_ waveform: Waveform, forEffect id: SoundEffect.ID) {
        guard effects.contains(where: { $0.id == id }) else { return }
        waveforms[id] = waveform
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
