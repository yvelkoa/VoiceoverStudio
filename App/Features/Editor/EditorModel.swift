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
        case generating, composing, exporting
    }

    struct Failure: Identifiable {
        let id = UUID()
        let message: String
        let recovery: ElevenLabsError.Recovery
        /// Repeats exactly the step that failed (an export retry must not re-spend generation credits).
        var retry: (() -> Void)?
    }

    var mode: Mode = .record {
        didSet { if mode != oldValue { recompose() } }
    }

    let project = Project()
    let recorder = TakeRecorder()

    // Type mode input
    var script = ""
    var voice: Voice?

    // Output
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
    private var recordingStart: Double = 0

    init(client: ElevenLabsClient) {
        self.client = client
    }

    var videoURL: URL? { project.videoURL }
    var videoDuration: Double { project.videoDuration }
    var effectStart: Double {
        get { project.effectStart }
        set { project.effectStart = newValue }
    }
    var effectPrompt: String {
        get { project.effectPrompt }
        set { project.effectPrompt = newValue }
    }

    var canGenerate: Bool {
        videoURL != nil && voice != nil && !trimmedScript.isEmpty && activity == nil
    }

    var canRecord: Bool {
        player != nil && project.activeCharacter != nil && activity == nil
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
    private var trimmedEffectPrompt: String { effectPrompt.trimmingCharacters(in: .whitespacesAndNewlines) }

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

    // MARK: - Record mode

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
        project.addTake(characterID: character.id, start: recordingStart, duration: duration, recording: url)
        player.seek(to: CMTime(seconds: recordingStart, preferredTimescale: 600))
        recompose()
    }

    func delete(_ take: Take) {
        project.remove(take)
        recompose()
    }

    // MARK: - Shared

    /// Re-builds the edit after something moved; no network involved.
    func recompose() {
        guard let videoURL else { return }
        run(.composing) {
            try await self.compose(videoURL: videoURL)
        }
    }

    func applyEffectStart() { recompose() }

    func export() {
        guard let composed, hasResult else { return }
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
        let clips = voiceClips() + effectClips()
        let wasPlaying = player?.rate ?? 0 > 0
        let resumeAt = player?.currentTime()

        let composed = try await VideoComposer.compose(
            video: videoURL,
            clips: clips,
            originalAudioVolume: clips.isEmpty ? 1 : VideoComposer.originalAudioVolume
        )
        try Task.checkCancellation()

        let item = AVPlayerItem(asset: composed.composition)
        item.audioMix = composed.audioMix
        item.videoComposition = composed.videoComposition
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
            return speechFile.map { [AudioClip(url: $0)] } ?? []
        case .record:
            let takes = Dictionary(uniqueKeysWithValues: project.takes.map { ($0.id, $0) })
            return project.segments.compactMap { segment in
                guard let take = takes[segment.takeID] else { return nil }
                // Converted audio keeps the take's timing, so the same offsets apply to it.
                let url = project.convertedAudio[take.id] ?? take.recording
                return AudioClip(url: url, start: segment.start, sourceOffset: segment.sourceOffset, duration: segment.duration)
            }
        }
    }

    private func effectClips() -> [AudioClip] {
        effectFile.map { [AudioClip(url: $0, start: effectStart)] } ?? []
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
