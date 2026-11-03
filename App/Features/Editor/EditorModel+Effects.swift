import AVFoundation
import Foundation
import VoiceoverKit

// Generated sound effects on their own lane.
extension EditorModel {
    /// Generates a sound from `prompt` and drops it on the timeline at `start`. One API call per effect.
    func addEffect(prompt: String, durationSeconds: Double?, at start: Double) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, activity == nil, let videoURL else { return }
        let retry: @MainActor () -> Void = { [weak self] in
            self?.addEffect(prompt: trimmed, durationSeconds: durationSeconds, at: start)
        }
        run(.generatingEffect, retry: retry, operation: { [client, project] in
            let data = try await client.soundEffect(prompt: trimmed, durationSeconds: durationSeconds)
            let url = try await Self.write(data, to: project.fileURL("effect", extension: "mp3"))
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            let effect = SoundEffect(id: UUID(), prompt: trimmed, start: start, duration: duration, audio: url)
            project.add(effect)
            try await self.compose(videoURL: videoURL)
            if let waveform = try? await Waveform.load(url) { project.setWaveform(waveform, for: effect.id) }
        })
    }

    func remove(_ effect: SoundEffect) {
        guard !isBusy else { return }
        project.remove(effect)
        recompose()
    }

    func move(_ effect: SoundEffect, to start: Double) {
        guard !isBusy else { return }
        project.move(effect, to: start)
        recompose()
    }
}
