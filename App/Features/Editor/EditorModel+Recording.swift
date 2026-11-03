import AVFoundation
import Foundation
import VoiceoverKit

// Record mode: punch-in takes, transcription for captions and the voice swap.
extension EditorModel {

    func startRecording() {
        guard canRecord, let player else { return }
        Task {
            guard await recorder.requestPermission() else {
                failure = Failure(message: TakeRecorder.Failure.microphoneDenied.localizedDescription, recovery: .none)
                return
            }
            do {
                recordingStart = player.currentTime().seconds
                // The video is silenced while recording so the microphone doesn't pick it up.
                player.isMuted = true
                _ = try recorder.start()
                player.play()
            } catch {
                player.isMuted = false
                failure = Failure(message: error.localizedDescription, recovery: .none)
            }
        }
    }

    func stopRecording() {
        guard isRecording, let player, let character = project.activeCharacter else { return }
        player.pause()
        player.isMuted = false
        let duration = recorder.stop()
        guard let url = recorder.lastRecordingURL, duration >= TakeResolver.minimumDuration else { return }
        let take = project.addTake(characterID: character.id, start: recordingStart, duration: duration, recording: url)
        player.seek(to: CMTime(seconds: recordingStart, preferredTimescale: 600))
        rebuildCaptions()
        recompose()
        transcribe(take)
    }

    func delete(_ take: Take) {
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
        guard canSwapVoices else { return }
        if let missing = project.charactersMissingVoice.first {
            failure = Failure(message: "Pick a voice for \(missing.name) first.", recovery: .editInput)
            return
        }
        let jobs = project.takesNeedingConversion.compactMap { take -> VoiceSwapper.Job? in
            guard let character = project.character(take.characterID), let voice = character.voice else { return nil }
            return VoiceSwapper.Job(take: take, voiceID: voice.voiceID, settings: character.settings)
        }
        run(.swapping) { [client, project] in
            try await VoiceSwapper.convert(jobs, client: client) { outcome in
                project.setConvertedAudio(outcome.audio, drift: outcome.drift, for: outcome.takeID)
            }
            self.recompose()
        }
    }
}
