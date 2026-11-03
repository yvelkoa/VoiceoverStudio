import AVFoundation
import Foundation
import VoiceoverKit

// Record mode: punch-in takes, transcription for captions and the voice swap.
extension EditorModel {

    /// The take being recorded right now, for the timeline.
    var liveRecording: LiveRecording? {
        guard isRecording, let character = project.activeCharacter else { return nil }
        return LiveRecording(characterID: character.id, start: recordingStart, waveform: Waveform(peaks: recorder.liveLevels))
    }

    func startRecording() {
        guard canRecord, let player else { return }
        isStartingRecording = true
        Task {
            defer { isStartingRecording = false }
            guard await recorder.requestPermission() else {
                failure = Failure(message: TakeRecorder.Failure.microphoneDenied.localizedDescription, recovery: .none)
                return
            }
            // The permission prompt can take a while; the screen may have moved on meanwhile.
            guard activity == nil, player === self.player else { return }
            do {
                recordingStart = player.currentTime().seconds
                // The video is silenced while recording so the microphone doesn't pick it up.
                player.isMuted = true
                _ = try recorder.start(in: project.folder)
                player.play()
            } catch {
                player.isMuted = false
                failure = Failure(message: error.localizedDescription, recovery: .none)
            }
        }
    }

    func stopRecording() {
        guard isRecording, let player, let character = project.activeCharacter else { return }
        player.rate = 0
        player.isMuted = false
        let duration = recorder.stop()
        guard let url = recorder.lastRecordingURL else { return }
        guard duration >= TakeResolver.minimumDuration else {
            // Too short to be a take; the file would otherwise sit in the project folder (and its backup) forever.
            try? FileManager.default.removeItem(at: url)
            return
        }
        let take = project.addTake(characterID: character.id, start: recordingStart, duration: duration, recording: url)
        player.seek(to: CMTime(seconds: recordingStart, preferredTimescale: 600))
        rebuildCaptions()
        recompose()
        transcribe(take)
        Task { [project] in
            if let waveform = try? await Waveform.load(take.recording) { project.setWaveform(waveform, for: take.id) }
        }
    }

    func delete(_ take: Take) {
        guard !isBusy else { return }
        transcriptions[take.id]?.cancel()
        transcriptions[take.id] = nil
        project.remove(take)
        rebuildCaptions()
        recompose()
    }

    /// Recognises the words in a take so captions can follow it. Runs alongside other work.
    func transcribe(_ take: Take) {
        transcriptions[take.id]?.cancel()
        transcriptions[take.id] = Task {
            defer { transcriptions[take.id] = nil }
            do {
                let words = try await Transcriber.words(in: take.recording, locale: RecordingLanguage.locale)
                guard !Task.isCancelled else { return }
                project.setTranscript(words, for: take.id)
                rebuildCaptions()
            } catch is CancellationError {
            } catch {
                failure = Failure(message: error.localizedDescription, recovery: .retry) { [weak self] in
                    self?.transcribe(take)
                }
            }
        }
    }

    // MARK: - Characters

    /// Character edits go through the model, not straight to the project: deleting a character drops its
    /// takes and files, and a new voice drops its conversions, so the edit has to be rebuilt afterwards.
    func addCharacter() {
        project.addCharacter(named: "Character \(project.characters.count + 1)")
    }

    func removeCharacter(_ id: Character.ID) {
        guard !isBusy, project.characters.count > 1 else { return }
        for take in project.takes where take.characterID == id {
            transcriptions[take.id]?.cancel()
            transcriptions[take.id] = nil
        }
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

    /// Replaces the recorded voice of every unconverted take with its character's ElevenLabs voice.
    func swapVoices() {
        guard canSwapVoices, let videoURL else { return }
        if let missing = project.charactersMissingVoice.first {
            failure = Failure(message: "Pick a voice for \(missing.name) first.", recovery: .editInput)
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
}
