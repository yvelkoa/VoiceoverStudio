import AVFoundation
import Foundation
import VoiceoverKit

// The steps that spend credits or minutes: Type-mode generation, export and the Photos save.
extension EditorModel {
    func generate() {
        guard canGenerate, let videoURL, let voice else { return }
        let script = trimmedScript
        resetResult()

        run(.generating, retry: { [weak self] in self?.generate() }, operation: { [client, project] in
            let generatedSpeech = try await client.speech(text: script, voiceID: voice.voiceID)
            project.speechFile = try await Self.write(generatedSpeech.audio, to: project.fileURL("speech", extension: "mp3"))
            project.typeCaptions = CaptionBuilder.captions(from: generatedSpeech.alignment)
            self.captions = project.typeCaptions
            try await self.compose(videoURL: videoURL)
        })
    }

    func export() {
        guard let composed, hasResult, !isBusy else { return }
        let captions = captions
        let levels = project.mix
        let range = project.isTrimmed ? project.trimRange : nil
        let output = project.fileURL("export", extension: "mp4")
        savedToPhotos = false
        run(.exporting, retry: { [weak self] in self?.export() }, operation: { [project] in
            let exported = try await VideoComposer.export(
                composed, captions: captions, levels: levels, range: range, to: output
            )
            // The previous export goes only once the new one exists; a failed export must not lose both.
            project.clearExport()
            project.exportedURL = exported
            // Straight into the library: that is where the result is wanted.
            try await PhotosSaver.save(output)
            self.savedToPhotos = true
        })
    }

    /// Adds the existing export to Photos again, e.g. after a relaunch or a denied permission.
    func saveToPhotos() {
        guard let url = exportedURL, !isBusy else { return }
        run(.saving, retry: { [weak self] in self?.saveToPhotos() }, operation: {
            try await PhotosSaver.save(url)
            self.savedToPhotos = true
        })
    }

    /// Drops the generated result, the player and the export before a new video or a regeneration.
    func resetResult() {
        player?.pause()
        player = nil
        composed = nil
        captions = []
        project.clearTypeResult()
        project.clearExport()
    }

    /// Generated MP3s are a few megabytes; writing them on the main actor was a visible hitch on the button.
    @concurrent
    nonisolated static func write(_ data: Data, to url: URL) async throws -> URL {
        try data.write(to: url)
        return url
    }
}
