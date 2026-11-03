import AVFoundation
import Foundation
import Observation
import VoiceoverKit

@Observable
final class EditorModel {
    typealias Mode = EditingMode

    enum Activity: Equatable {
        case generating, generatingEffect, composing, exporting, swapping, saving
    }

    struct Failure: Identifiable {
        let id = UUID()
        let message: String
        let recovery: ElevenLabsError.Recovery
        /// Repeats exactly the step that failed (an export retry must not re-spend generation credits).
        var retry: (() -> Void)?
    }

    var mode: Mode {
        get { project.mode }
        set {
            guard newValue != project.mode else { return }
            project.mode = newValue
            switch newValue {
            case .record: rebuildCaptions()
            case .type: captions = project.typeCaptions
            }
            recompose()
        }
    }

    let project: Project
    let recorder = TakeRecorder()

    // Type mode input, stored on the project so it survives relaunch
    var script: String {
        get { project.script }
        set { project.script = newValue }
    }
    var voice: Voice? {
        get { project.voice }
        set { project.voice = newValue }
    }

    // Output
    /// Written by the model and its extensions; views only read it.
    var captions: [Caption] = []
    private(set) var player: AVPlayer?
    var exportedURL: URL? { project.exportedURL }
    /// The current export has been added to the photo library.
    private(set) var savedToPhotos = false
    private(set) var activity: Activity?
    var failure: Failure?

    let client: ElevenLabsClient

    private var speechFile: URL? { project.speechFile }
    private var composed: ComposedVideo?
    /// Thumbnails for the scrubber, decoded once per video; decoding 60 fps frames on every open stuttered.
    private(set) var frameStrip: CGImage?
    private var frameStripTask: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var autosaver: ProjectAutosaver?
    var recordingStart: Double = 0
    var transcriptions: [Take.ID: Task<Void, Never>] = [:]

    init(project: Project, client: ElevenLabsClient, store: ProjectStore?) {
        self.project = project
        self.client = client
        if let store { autosaver = ProjectAutosaver(project: project, store: store) }
        restore()
    }

    /// The editor is gone when the screen that owned it is popped: flush the last changes and stop playback.
    /// (Not onDisappear: that also fires when a picker is pushed on top, and must not cancel an export.)
    isolated deinit {
        work?.cancel()
        frameStripTask?.cancel()
        for task in transcriptions.values { task.cancel() }
        player?.pause()
        autosaver?.stop()
    }

    /// Brings a loaded project back to life: captions, waveforms and the player.
    private func restore() {
        switch mode {
        case .record: rebuildCaptions()
        case .type: captions = project.typeCaptions
        }
        recompose()
        let sources = project.takes.map { ($0.id, $0.recording) } + project.effects.map { ($0.id, $0.audio) }
        for (id, url) in sources {
            Task(priority: .utility) { [project] in
                if let waveform = try? await Waveform.load(url) { project.setWaveform(waveform, for: id) }
            }
        }
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

    /// Starts decoding the scrubber strip in the background if it isn't there yet.
    func loadFrameStrip(cellSize: CGSize, scale: CGFloat) {
        guard frameStrip == nil, frameStripTask == nil, let videoURL, videoDuration > 0 else { return }
        frameStripTask = Task(priority: .utility) {
            let image = try? await FrameStrip.image(
                for: videoURL, duration: videoDuration, interval: 1, cellSize: cellSize, scale: scale
            )
            if !Task.isCancelled { frameStrip = image }
            frameStripTask = nil
        }
    }

    /// Moves a picked video into the project folder and starts over with it.
    func setVideo(_ picked: URL) async {
        cancel()
        resetResult()
        frameStripTask?.cancel()
        frameStripTask = nil
        frameStrip = nil
        let destination = project.fileURL("video", extension: picked.pathExtension.isEmpty ? "mov" : picked.pathExtension)
        do {
            if picked.path.hasPrefix(URL.temporaryDirectory.path) {
                // Our own copy from the picker: move it, nothing else needs it.
                try FileManager.default.moveItem(at: picked, to: destination)
            } else {
                try FileManager.default.copyItem(at: picked, to: destination)
            }
        } catch {
            failure = Failure(message: "Couldn't store this video.", recovery: .none)
            return
        }
        let duration = (try? await AVURLAsset(url: destination).load(.duration).seconds) ?? 0
        project.setVideo(destination, duration: duration)
        recompose()
        let thumbnail = project.folder.appending(path: ProjectDocument.thumbnailName)
        Task { try? await Thumbnail.write(for: destination, to: thumbnail) }
    }

    // MARK: - Type mode

    func generate() {
        guard canGenerate, let videoURL, let voice else { return }
        let script = trimmedScript
        resetResult()

        run(.generating) { [client, project] in
            let generatedSpeech = try await client.speech(text: script, voiceID: voice.voiceID)
            project.speechFile = try Self.write(generatedSpeech.audio, to: project.fileURL("speech", extension: "mp3"))
            project.typeCaptions = CaptionBuilder.captions(from: generatedSpeech.alignment)
            self.captions = project.typeCaptions
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
        let range = project.isTrimmed ? project.trimRange : nil
        let output = project.fileURL("export", extension: "mp4")
        savedToPhotos = false
        run(.exporting) { [project] in
            project.clearExport()
            project.exportedURL = try await VideoComposer.export(
                composed, captions: captions, levels: levels, range: range, to: output
            )
            // Straight into the library: that is where the result is wanted.
            try await PhotosSaver.save(output)
            self.savedToPhotos = true
        }
    }

    /// Adds the existing export to Photos again, e.g. after a relaunch or a denied permission.
    func saveToPhotos() {
        guard let url = exportedURL else { return }
        run(.saving) {
            try await PhotosSaver.save(url)
            self.savedToPhotos = true
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
        // AVPlayerItem is main-actor bound in iOS 26; creating it is cheap, loading happens asynchronously.
        let item = AVPlayerItem(asset: composed.composition)
        var levels = project.mix
        if clips.isEmpty { levels.original = 1 } // nothing to duck under yet
        item.audioMix = composed.audioMix(levels)
        self.composed = composed
        project.clearExport()
        savedToPhotos = false
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
        project.clearTypeResult()
        project.clearExport()
    }

    nonisolated static func write(_ data: Data, to url: URL) throws -> URL {
        try data.write(to: url)
        return url
    }
}
