import AVFoundation
import Foundation
import VoiceoverKit

// Background music: one generated track under the whole video.
extension EditorModel {

    /// Composes an instrumental track from `prompt` as long as the export range and lays it under the edit
    /// from the range's start, replacing the previous one. One API call; the old track is deleted only once
    /// the new one is in.
    func generateMusic(prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, activity == nil, let videoURL, videoDuration > 0 else { return }
        let seconds = musicLength

        let retry: @MainActor () -> Void = { [weak self] in self?.generateMusic(prompt: trimmed) }
        run(.generatingMusic, retry: retry, operation: { [client, project, services] in
            let data = try await client.music(prompt: trimmed, seconds: seconds)
            let url = try await Self.write(data, to: project.fileURL("music", extension: "mp3"))
            let duration = try await services.duration(url)

            let music = BackgroundMusic(prompt: trimmed, duration: duration, audio: url)
            project.setMusic(music)
            try await self.compose(videoURL: videoURL)

            if let waveform = try? await services.waveform(url) { project.setWaveform(waveform, for: music.id) }
        })
    }

    /// Seconds of music a generation asks for: the part of the video that gets exported. Shown before
    /// generating, since the API bills by length.
    var musicLength: Double {
        let range = project.trimRange
        return range.upperBound - range.lowerBound
    }

    func removeMusic() {
        guard !isBusy, project.music != nil else { return }
        project.removeMusic()
        recompose()
    }
}
