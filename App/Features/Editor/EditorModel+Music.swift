import AVFoundation
import Foundation
import VoiceoverKit

// Background music: one generated track under the whole video.
extension EditorModel {

    /// Composes an instrumental track from `prompt` as long as the video and lays it under the edit,
    /// replacing the previous one. One API call; the old track is deleted only once the new one is in.
    func generateMusic(prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, activity == nil, let videoURL, videoDuration > 0 else { return }
        let seconds = videoDuration

        run(.generatingMusic, retry: { [weak self] in self?.generateMusic(prompt: trimmed) }, operation: { [client, project] in
            let data = try await client.music(prompt: trimmed, seconds: seconds)
            let url = try await Self.write(data, to: project.fileURL("music", extension: "mp3"))
            let duration = try await AVURLAsset(url: url).load(.duration).seconds

            let music = BackgroundMusic(prompt: trimmed, duration: duration, audio: url)
            project.setMusic(music)
            try await self.compose(videoURL: videoURL)

            if let waveform = try? await Waveform.load(url) { project.setWaveform(waveform, for: music.id) }
        })
    }

    func removeMusic() {
        guard !isBusy, project.music != nil else { return }
        project.removeMusic()
        recompose()
    }
}
