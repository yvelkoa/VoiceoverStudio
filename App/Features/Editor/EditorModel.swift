import AVFoundation
import Foundation
import Observation
import VoiceoverKit

@Observable
final class EditorModel {
    enum Activity: Equatable {
        case generating, composing, exporting
    }

    struct Failure: Identifiable {
        let id = UUID()
        let message: String
        let recovery: ElevenLabsError.Recovery
        /// Repeats exactly the step that failed (an export retry must not re-spend generation credits).
        var retry: (() -> Void)?
    }

    // Input
    var script = ""
    var voice: Voice?
    var effectPrompt = ""
    var effectStart: Double = 0

    // Output
    private(set) var videoURL: URL?
    private(set) var videoDuration: Double = 0
    private(set) var captions: [Caption] = []
    private(set) var player: AVPlayer?
    private(set) var exportedURL: URL?
    private(set) var activity: Activity?
    var failure: Failure?

    let client: ElevenLabsClient

    /// Generated audio is kept on disk so moving the sound effect re-composes without new API calls.
    private var speechFile: URL?
    private var effectFile: URL?
    private var composed: ComposedVideo?
    private var work: Task<Void, Never>?

    init(client: ElevenLabsClient) {
        self.client = client
    }

    var canGenerate: Bool {
        videoURL != nil && voice != nil && !trimmedScript.isEmpty && activity == nil
    }

    var hasResult: Bool { composed != nil }

    private var trimmedScript: String { script.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEffectPrompt: String { effectPrompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Actions

    func setVideo(_ url: URL) async {
        cancel()
        resetResult()
        videoURL = url
        videoDuration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        effectStart = min(effectStart, videoDuration)
    }

    func generate() {
        guard canGenerate, let videoURL, let voice else { return }
        let script = trimmedScript
        let effectPrompt = trimmedEffectPrompt
        resetResult()

        run(.generating) { [client] in
            // Voice and sound effect don't depend on each other, so request them in parallel.
            async let speech = client.speech(text: script, voiceID: voice.voiceID)
            async let effect = Self.effect(prompt: effectPrompt, client: client)
            let (generatedSpeech, effectData) = try await (speech, effect)

            self.speechFile = try Self.write(generatedSpeech.audio, name: "speech")
            self.effectFile = try effectData.map { try Self.write($0, name: "effect") }
            self.captions = CaptionBuilder.captions(from: generatedSpeech.alignment)
            try await self.compose(videoURL: videoURL)
        }
    }

    /// Re-builds the edit after the sound effect was moved; no network involved.
    func applyEffectStart() {
        guard let videoURL, speechFile != nil, effectFile != nil else { return }
        run(.composing) {
            try await self.compose(videoURL: videoURL)
        }
    }

    func export() {
        guard let composed else { return }
        let captions = captions
        run(.exporting) {
            self.exportedURL = try await VideoComposer.export(composed, captions: captions)
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
        activity = nil
    }

    // MARK: - Private

    private func run(_ activity: Activity, _ operation: @escaping () async throws -> Void) {
        work?.cancel()
        self.activity = activity
        work = Task {
            do {
                try await operation()
            } catch is CancellationError {
                // The user cancelled or started something newer; nothing to report.
            } catch let error as ElevenLabsError {
                failure = Failure(message: error.localizedDescription, recovery: error.recovery) { [weak self] in
                    self?.run(activity, operation)
                }
            } catch {
                failure = Failure(message: error.localizedDescription, recovery: .retry) { [weak self] in
                    self?.run(activity, operation)
                }
            }
            if !Task.isCancelled { self.activity = nil }
        }
    }

    private func compose(videoURL: URL) async throws {
        guard let speechFile else { return }
        var clips = [AudioClip(url: speechFile)]
        if let effectFile {
            clips.append(AudioClip(url: effectFile, start: effectStart))
        }
        let composed = try await VideoComposer.compose(video: videoURL, clips: clips)
        try Task.checkCancellation()

        let item = AVPlayerItem(asset: composed.composition)
        item.audioMix = composed.audioMix
        item.videoComposition = composed.videoComposition
        self.composed = composed
        exportedURL = nil
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }
    }

    private func resetResult() {
        player?.pause()
        player = nil
        composed = nil
        captions = []
        exportedURL = nil
        speechFile = nil
        effectFile = nil
    }

    nonisolated private static func effect(prompt: String, client: ElevenLabsClient) async throws -> Data? {
        guard !prompt.isEmpty else { return nil }
        return try await client.soundEffect(prompt: prompt)
    }

    nonisolated private static func write(_ data: Data, name: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString).mp3")
        try data.write(to: url)
        return url
    }
}
