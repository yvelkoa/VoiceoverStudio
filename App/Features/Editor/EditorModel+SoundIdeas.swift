import Foundation
import VoiceoverKit

// Suggested sounds: the on-device model reads the captions, the user picks, ElevenLabs generates.
extension EditorModel {

    /// Asks for a fresh plan from what is said in the video. In Record mode the words are in the
    /// recording language, so it is checked up front; a typed script can be in any language.
    func suggestSounds() {
        let locale = mode == .record ? services.recordingLocale() : nil
        soundIdeas.suggest(from: captions, videoDuration: videoDuration, locale: locale)
    }

    func prewarmSoundIdeas() {
        services.prewarmSoundDirector()
    }

    /// Generates the picked effects one after another and lays them on the effects lane, then rebuilds the
    /// edit once. One API call per effect. A retry after a failure skips the ones that already landed.
    func addEffects(_ planned: [SoundPlan.Effect]) {
        guard activity == nil, videoURL != nil else { return }
        let missing = planned.filter { effect in
            !project.effects.contains { $0.prompt == effect.prompt && $0.start == effect.start }
        }
        guard !missing.isEmpty else { return }

        let retry: @MainActor () -> Void = { [weak self] in self?.addEffects(planned) }
        run(.generatingEffects, retry: retry, operation: { [client, project, services] in
            var added: [SoundEffect] = []
            // Whatever made it in is kept and heard even if a later effect fails.
            defer {
                if !added.isEmpty { self.recompose() }
            }
            for effect in missing {
                try Task.checkCancellation()
                let data = try await client.soundEffect(prompt: effect.prompt, durationSeconds: effect.duration)
                let url = try await Self.write(data, to: project.fileURL("effect", extension: "mp3"))
                let duration = try await services.duration(url)
                let sound = SoundEffect(id: UUID(), prompt: effect.prompt, start: effect.start, duration: duration, audio: url)
                project.add(sound)
                added.append(sound)
            }
            for sound in added {
                if let waveform = try? await services.waveform(sound.audio) { project.setWaveform(waveform, for: sound.id) }
            }
        })
    }
}
