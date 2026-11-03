import AVFoundation
import Foundation
import Observation
import VoiceoverKit

@Observable
final class EditorModel {
    enum Mode: Hashable {
        /// Type a script; ElevenLabs reads it.
        case type
        /// Record takes with the microphone; ElevenLabs swaps the voice later.
        case record
    }

    enum Activity: Equatable {
        case generating, generatingEffect, composing, exporting, swapping
    }

    struct Failure: Identifiable {
        let id = UUID()
        let message: String
        let recovery: ElevenLabsError.Recovery
        /// Repeats exactly the step that failed (an export retry must not re-spend generation credits).
        var retry: (() -> Void)?
    }

    var mode: Mode = .record {
        didSet {
            guard mode != oldValue else { return }
            switch mode {
            case .record: rebuildCaptions()
            case .type: captions = typeCaptions
            }
            recompose()
        }
    }

    let project = Project()
    let recorder = TakeRecorder()

    // Type mode input
    var script = ""
    var voice: Voice?

    // Output
    /// Written by the model and its extensions; views only read it.
    var captions: [Caption] = []
    private(set) var player: AVPlayer?
    private(set) var exportedURL: URL?
    private(set) var activity: Activity?
    var failure: Failure?

    let client: ElevenLabsClient

    /// Generated audio is kept on disk so moving the sound effect re-composes without new API calls.
    private var speechFile: URL?
    private var typeCaptions: [Caption] = []
    private var effectFile: URL?
    private var composed: ComposedVideo?
    private var work: Task<Void, Never>?
    var recordingStart: Double = 0
    var transcriptions: [Take.ID: Task<Void, Never>] = [:]

    init(client: ElevenLabsClient) {
        self.client = client
    }

    var videoURL: URL? { project.videoURL }
    var videoDuration: Double { project.videoDuration }

    var canGenerate: Bool {
        videoURL != nil && voice != nil && !trimmedScript.isEmpty && activity == nil
    }

    var canRecord: Bool {
        player != nil && project.activeCharacter != nil && activity == nil
    }

    var canSwapVoices: Bool {
        mode == .record && !project.takesNeedingConversion.isEmpty && activity == nil && !isRecording
    }

    var isRecording: Bool { recorder.isRecording }

    /// Something worth exporting: generated speech in Type mode, at least one take in Record mode.
    var hasResult: Bool {
        switch mode {
        case .type: speechFile != nil
        case .record: !project.takes.isEmpty
        }
    }

    private var trimmedScript: String { script.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Video

    func setVideo(_ url: URL) async {
        cancel()
        resetResult()
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        project.setVideo(url, duration: duration)
        recompose()
    }

    // MARK: - Type mode

    func generate() {
        guard canGenerate, let videoURL, let voice else { return }
        let script = trimmedScript
        resetResult()

        run(.generating) { [client] in
            let generatedSpeech = try await client.speech(text: script, voiceID: voice.voiceID)
            self.speechFile = try Self.write(generatedSpeech.audio, name: "speech")
            self.typeCaptions = CaptionBuilder.captions(from: generatedSpeech.alignment)
            self.captions = self.typeCaptions
            try await self.compose(videoURL: videoURL)
        }
    }

    // MARK: - Shared

    /// Re-builds the edit after something moved; no network involved.
    func recompose() {
        guard let videoURL else { return }
        run(.composing) {
            try await self.compose(videoURL: videoURL)
        }
    }

    /// Pushes the project's mix levels onto the playing item without rebuilding anything.
    func applyMix() {
        guard let composed else { return }
        player?.currentItem?.audioMix = composed.audioMix(project.mix)
    }

    func export() {
        guard let composed, hasResult else { return }
        let captions = captions
        let levels = project.mix
        run(.exporting) {
            self.exportedURL = try await VideoComposer.export(composed, captions: captions, levels: levels)
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
        activity = nil
    }

    // MARK: - Private

    func run(_ activity: Activity, _ operation: @escaping () async throws -> Void) {
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
        let clips = voiceClips() + effectClips()
        let wasPlaying = player?.rate ?? 0 > 0
        let resumeAt = player?.currentTime()

        let composed = try await VideoComposer.compose(video: videoURL, clips: clips)
        try Task.checkCancellation()

        // No video composition for the preview: AVPlayer applies the track's preferredTransform itself and
        // captions are a SwiftUI overlay. The compositor is only needed for the export, and in the simulator
        // its frames can't be displayed by AVPlayerLayer at all (IQ-CA error -19230, black video).
        let item = AVPlayerItem(asset: composed.composition)
        var levels = project.mix
        if clips.isEmpty { levels.original = 1 } // nothing to duck under yet
        item.audioMix = composed.audioMix(levels)
        self.composed = composed
        exportedURL = nil
        if let player {
            player.replaceCurrentItem(with: item)
            if let resumeAt { await player.seek(to: resumeAt) }
            if wasPlaying { player.play() }
        } else {
            player = AVPlayer(playerItem: item)
        }
    }

    private func voiceClips() -> [AudioClip] {
        switch mode {
        case .type:
            return speechFile.map { [AudioClip(url: $0, kind: .voice)] } ?? []
        case .record:
            let takes = Dictionary(uniqueKeysWithValues: project.takes.map { ($0.id, $0) })
            return project.segments.compactMap { segment in
                guard let take = takes[segment.takeID] else { return nil }
                // Converted audio keeps the take's timing, so the same offsets apply to it.
                let url = project.convertedAudio[take.id] ?? take.recording
                return AudioClip(
                    url: url,
                    kind: .voice,
                    start: segment.start,
                    sourceOffset: segment.sourceOffset,
                    duration: segment.duration
                )
            }
        }
    }

    private func effectClips() -> [AudioClip] {
        project.effects.map { AudioClip(url: $0.audio, kind: .effect, start: $0.start) }
    }

    private func resetResult() {
        player?.pause()
        player = nil
        composed = nil
        captions = []
        typeCaptions = []
        exportedURL = nil
        speechFile = nil
    }

    nonisolated static func write(_ data: Data, name: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString).mp3")
        try data.write(to: url)
        return url
    }
}
