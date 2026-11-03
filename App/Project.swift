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
/// Every file it refers to lives inside `folder`, so a project is self-contained on disk.
@Observable
final class Project: Identifiable {
    let id: UUID
    let folder: URL
    var title: String
    let createdAt: Date
    var updatedAt: Date

    private(set) var videoURL: URL?
    private(set) var videoDuration: Double = 0

    var mode: EditingMode = .record
    private(set) var characters: [Character] = []
    var activeCharacterID: Character.ID?
    private(set) var takes: [Take] = []

    /// Words recognised in each take, with times relative to the take's start.
    private(set) var transcripts: [Take.ID: [TimedWord]] = [:]
    /// The same take spoken by the character's ElevenLabs voice.
    private(set) var convertedAudio: [Take.ID: URL] = [:]
    /// Seconds the converted audio is longer (or shorter) than the recording. Large values desync captions.
    private(set) var conversionDrift: [Take.ID: Double] = [:]
    /// Peak levels of each recording or effect, for the timeline. Rebuilt on load, not stored.
    private(set) var waveforms: [UUID: Waveform] = [:]

    private(set) var effects: [SoundEffect] = []

    /// Mix levels, 0...1. Used by the preview and the export alike.
    var mix = MixLevels()

    /// Export range in seconds; nil ends mean the video's own start or end.
    var trimStart: Double?
    var trimEnd: Double?

    // Type mode
    var script = ""
    var voice: Voice?
    var speechFile: URL?
    var typeCaptions: [Caption] = []

    /// The last export, if it is still current.
    var exportedURL: URL?

    private var nextSequence = 0

    init(folder: URL, title: String) {
        id = UUID(uuidString: folder.lastPathComponent) ?? UUID()
        self.folder = folder
        self.title = title
        createdAt = .now
        updatedAt = createdAt
        addCharacter(named: "Narrator")
    }

    init(document: ProjectDocument, folder: URL) {
        id = document.id
        self.folder = folder
        title = document.title
        createdAt = document.createdAt
        updatedAt = document.updatedAt
        videoURL = document.videoFile.map { folder.appending(path: $0) }
        videoDuration = document.videoDuration
        mode = document.mode
        characters = document.characters
        activeCharacterID = document.activeCharacterID ?? document.characters.first?.id
        takes = document.takes.map {
            Take(
                id: $0.id,
                characterID: $0.characterID,
                start: $0.start,
                duration: $0.duration,
                recording: folder.appending(path: $0.file),
                sequence: $0.sequence
            )
        }
        nextSequence = document.nextSequence
        transcripts = Dictionary(uniqueKeysWithValues: document.transcripts.compactMap { key, words in
            UUID(uuidString: key).map { ($0, words) }
        })
        convertedAudio = Dictionary(uniqueKeysWithValues: document.convertedAudio.compactMap { key, file in
            UUID(uuidString: key).map { ($0, folder.appending(path: file)) }
        })
        conversionDrift = Dictionary(uniqueKeysWithValues: document.conversionDrift.compactMap { key, drift in
            UUID(uuidString: key).map { ($0, drift) }
        })
        effects = document.effects.map {
            SoundEffect(
                id: $0.id, prompt: $0.prompt, start: $0.start, duration: $0.duration, audio: folder.appending(path: $0.file)
            )
        }
        mix = document.mix
        trimStart = document.trimStart
        trimEnd = document.trimEnd
        script = document.script
        voice = document.voice
        speechFile = document.speechFile.map { folder.appending(path: $0) }
        typeCaptions = document.typeCaptions
        exportedURL = document.exportFile.map { folder.appending(path: $0) }
    }

    /// Snapshot for disk. Reading it touches every persisted property, which is what the autosaver tracks.
    var document: ProjectDocument {
        ProjectDocument(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            videoFile: videoURL?.lastPathComponent,
            videoDuration: videoDuration,
            mode: mode,
            characters: characters,
            activeCharacterID: activeCharacterID,
            takes: takes.map {
                .init(id: $0.id, characterID: $0.characterID, start: $0.start, duration: $0.duration,
                      file: $0.recording.lastPathComponent, sequence: $0.sequence)
            },
            nextSequence: nextSequence,
            transcripts: Dictionary(uniqueKeysWithValues: transcripts.map { ($0.key.uuidString, $0.value) }),
            convertedAudio: Dictionary(uniqueKeysWithValues: convertedAudio.map {
                ($0.key.uuidString, $0.value.lastPathComponent)
            }),
            conversionDrift: Dictionary(uniqueKeysWithValues: conversionDrift.map { ($0.key.uuidString, $0.value) }),
            effects: effects.map {
                .init(id: $0.id, prompt: $0.prompt, start: $0.start, duration: $0.duration, file: $0.audio.lastPathComponent)
            },
            mix: mix,
            trimStart: trimStart,
            trimEnd: trimEnd,
            script: script,
            voice: voice,
            speechFile: speechFile?.lastPathComponent,
            typeCaptions: typeCaptions,
            exportFile: exportedURL?.lastPathComponent
        )
    }

    /// A new file inside the project folder.
    func fileURL(_ prefix: String, extension ext: String) -> URL {
        folder.appending(path: "\(prefix)-\(UUID().uuidString).\(ext)")
    }

    var trimRange: ClosedRange<Double> {
        let start = trimStart ?? 0
        let end = trimEnd ?? videoDuration
        return start...max(end, start + 0.1)
    }

    var isTrimmed: Bool { trimStart != nil || trimEnd != nil }

    var activeCharacter: Character? {
        characters.first { $0.id == activeCharacterID }
    }

    /// The audible slices after overlap resolution, in timeline order.
    var segments: [AudioSegment] { TakeResolver.segments(for: takes) }

    func character(_ id: Character.ID) -> Character? {
        characters.first { $0.id == id }
    }

    // MARK: - Video

    /// `url` must already be inside the project folder. Everything recorded for the old video is dropped.
    func setVideo(_ url: URL, duration: Double) {
        if let videoURL, videoURL != url { try? FileManager.default.removeItem(at: videoURL) }
        videoURL = url
        videoDuration = duration
        trimStart = nil
        trimEnd = nil
        for effect in effects { try? FileManager.default.removeItem(at: effect.audio) }
        effects.removeAll()
        for take in takes { try? FileManager.default.removeItem(at: take.recording) }
        for converted in convertedAudio.values { try? FileManager.default.removeItem(at: converted) }
        takes.removeAll()
        transcripts.removeAll()
        convertedAudio.removeAll()
        conversionDrift.removeAll()
        waveforms.removeAll()
        clearTypeResult()
        clearExport()
    }

    func clearTypeResult() {
        if let speechFile { try? FileManager.default.removeItem(at: speechFile) }
        speechFile = nil
        typeCaptions = []
    }

    func clearExport() {
        if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
        exportedURL = nil
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
                if let converted = convertedAudio[take.id] { try? FileManager.default.removeItem(at: converted) }
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
        if let converted = convertedAudio[take.id] { try? FileManager.default.removeItem(at: converted) }
        convertedAudio[take.id] = nil
        conversionDrift[take.id] = nil
        waveforms[take.id] = nil
        try? FileManager.default.removeItem(at: take.recording)
    }

    func setWaveform(_ waveform: Waveform, for id: UUID) {
        waveforms[id] = waveform
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

    /// Takes whose converted audio is missing or stale.
    var takesNeedingConversion: [Take] {
        takes.filter { convertedAudio[$0.id] == nil }
    }

    /// Total seconds that a voice swap would send to ElevenLabs; the API bills by audio length.
    var secondsNeedingConversion: Double {
        takesNeedingConversion.reduce(0) { $0 + $1.duration }
    }
}
