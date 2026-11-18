import AVFoundation
import Foundation
import VoiceoverKit

// Record mode: punch-in takes, who speaks them, captions from their transcripts, the voice swap and the trim.
extension EditorModel {

    // MARK: - Takes

    /// The take being recorded right now, for the timeline.
    var liveRecording: LiveRecording? { recording.live }

    func startRecording() {
        guard canRecord, let player, let character = project.activeCharacter else { return }

        Task {
            do {
                try await recording.start(for: character.id, player: player, in: project.folder) { [weak self] in
                    self?.activity == nil && self?.player === player
                }
            } catch {
                failure = Failure(message: error.localizedDescription, recovery: .none)
            }
        }
    }

    func stopRecording() {
        guard let player, let finished = recording.stop(player: player) else { return }

        let take = project.addTake(
            characterID: finished.characterID, start: finished.start, duration: finished.duration, recording: finished.recording
        )
        rebuildCaptions()
        recompose()
        transcriptions.transcribe(take)
        Task { [project] in
            if let waveform = try? await Waveform.load(take.recording) { project.setWaveform(waveform, for: take.id) }
        }
    }

    func delete(_ take: Take) {
        guard !isBusy else { return }
        transcriptions.cancel(take.id)

        project.remove(take)
        rebuildCaptions()
        recompose()
    }

    // MARK: - Captions

    /// Captions for Record mode: each character's words on its own line, cut to the audible segments.
    func rebuildCaptions() {
        guard mode == .record else { return }
        captions = CaptionAssembler.captions(
            segments: project.segments,
            takes: project.takes,
            transcripts: project.transcripts,
            characterOrder: project.characters.map(\.id)
        )
    }

    // MARK: - Characters

    /// Character edits go through the model, not straight to the project: deleting a character drops its
    /// takes and files, and a new voice drops its conversions, so the edit has to be rebuilt afterwards.
    func addCharacter() {
        project.addCharacter(named: String(localized: "Character \(project.characters.count + 1)"))
    }

    func removeCharacter(_ id: Character.ID) {
        guard !isBusy, project.characters.count > 1 else { return }
        transcriptions.cancel(project.takes.filter { $0.characterID == id }.map(\.id))

        project.removeCharacter(id)
        rebuildCaptions()
        recompose()
    }

    func update(_ character: Character) {
        guard let current = project.character(character.id) else { return }
        let needsRecompose = current.voice != character.voice || current.settings != character.settings
        if needsRecompose && isBusy { return } // a swap is using those conversions right now

        project.update(character)
        if needsRecompose { recompose() }
    }

    // MARK: - Voice swap

    /// Replaces the recorded voice of every unconverted take with its character's ElevenLabs voice.
    func swapVoices() {
        guard canSwapVoices, let videoURL else { return }
        if let missing = project.charactersMissingVoice.first {
            failure = Failure(message: String(localized: "Pick a voice for \(missing.name) first."), recovery: .editInput)
            return
        }

        let jobs = project.takesNeedingConversion.compactMap { take -> VoiceSwapper.Job? in
            guard let character = project.character(take.characterID), let voice = character.voice else { return nil }
            return VoiceSwapper.Job(take: take, voiceID: voice.voiceID, settings: character.settings)
        }

        run(.swapping, retry: { [weak self] in self?.swapVoices() }, operation: { [client, project] in
            try await VoiceSwapper.convert(jobs, client: client, into: project.folder) { outcome in
                project.setConvertedAudio(outcome.audio, drift: outcome.drift, for: outcome.takeID)
            }
            try await self.compose(videoURL: videoURL)
        })
    }

    // MARK: - Trim

    /// The export range. Only the export reads it, so no recompose; but the current export no longer
    /// matches it and is dropped.
    func setTrim(start: Double? = nil, end: Double? = nil, clear: Bool = false) {
        if clear {
            project.trimStart = nil
            project.trimEnd = nil
        }
        if let start {
            project.trimStart = start
            if let end = project.trimEnd, end <= start { project.trimEnd = nil }
        }
        if let end {
            project.trimEnd = end
            if let start = project.trimStart, start >= end { project.trimStart = nil }
        }

        project.clearExport()
        savedToPhotos = false
    }
}
