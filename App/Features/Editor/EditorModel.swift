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
        /// Built from a weak reference to the model and plain values only: a failure is stored on the model,
        /// so a retry that captured the operation (and through it `self`) would keep the editor alive.
        var retry: (() -> Void)?
    }

    /// Where a piece of work runs. Composing is cheap and restartable; a job spends credits or minutes.
    /// Keeping them apart means a recompose can never cancel a swap or an export.
    enum Slot { case compose, job }

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
    /// Written by the model and its extensions; views only read it.
    var player: AVPlayer?
    var exportedURL: URL? { project.exportedURL }
    /// The current export has been added to the photo library.
    var savedToPhotos = false
    private(set) var activity: Activity?
    var failure: Failure?

    let client: ElevenLabsClient

    var speechFile: URL? { project.speechFile }
    var composed: ComposedVideo?
    /// Thumbnails for the scrubber, decoded once per video; decoding 60 fps frames on every open stuttered.
    private(set) var frameStrip: CGImage?
    private var frameStripTask: Task<Void, Never>?
    /// Waveform decodes for the takes and effects of a loaded project; cancelled with the editor.
    private var waveformTask: Task<Void, Never>?
    private var composeTask: Task<Void, Never>?
    private var jobTask: Task<Void, Never>?
    /// A recompose was requested while a job ran; it happens when the job is done.
    private var needsRecompose = false
    private var autosaver: ProjectAutosaver?
    var recordingStart: Double = 0
    /// Record was pressed and the microphone permission is being asked; a second press must not start a
    /// second recorder.
    var isStartingRecording = false
    var transcriptions: [Take.ID: Task<Void, Never>] = [:]

    init(project: Project, client: ElevenLabsClient, store: ProjectStore?) {
        self.project = project
        self.client = client
        if let store { autosaver = ProjectAutosaver(project: project, store: store) }
        // A call or an unplugged headset ends the take the same way Stop does, keeping what was recorded.
        recorder.onInterruption = { [weak self] in self?.stopRecording() }
        restore()
    }

    /// The editor is gone when the screen that owned it is popped: flush the last changes and stop playback.
    /// (Not onDisappear: that also fires when a picker is pushed on top, and must not cancel an export.)
    isolated deinit {
        composeTask?.cancel()
        jobTask?.cancel()
        frameStripTask?.cancel()
        waveformTask?.cancel()
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
        waveformTask = Task(priority: .utility) { [project] in
            await withTaskGroup { group in
                for (id, url) in sources {
                    group.addTask { try? await Waveform.load(url) }
                    // One at a time keeps the decoder from competing with the player that just started.
                    if let waveform = await group.next(), let waveform { project.setWaveform(waveform, for: id) }
                }
            }
        }
    }

    var videoURL: URL? { project.videoURL }
    var videoDuration: Double { project.videoDuration }

    var canGenerate: Bool {
        videoURL != nil && voice != nil && !trimmedScript.isEmpty && activity == nil
    }

    var canRecord: Bool {
        player != nil && project.activeCharacter != nil && activity == nil && !isStartingRecording && !isRecording
    }

    var canSwapVoices: Bool {
        mode == .record && !project.takesNeedingConversion.isEmpty && activity == nil && !isRecording
    }

    var isRecording: Bool { recorder.isRecording }

    /// A swap, export, generation or save is running. Edits that change the composition wait until it is done,
    /// so the job is never cancelled by accident (a cancelled swap has already been billed).
    var isBusy: Bool { jobTask != nil }

    /// Something worth exporting: generated speech in Type mode, at least one take in Record mode.
    var hasResult: Bool {
        switch mode {
        case .type: speechFile != nil
        case .record: !project.takes.isEmpty
        }
    }

    var trimmedScript: String { script.trimmingCharacters(in: .whitespacesAndNewlines) }

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
        guard !isBusy else { return }
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

    // MARK: - Shared

    /// Re-builds the edit after something moved; no network involved. Deferred while a job runs.
    func recompose() {
        guard let videoURL else { return }
        if isBusy {
            needsRecompose = true
            return
        }
        run(.composing, slot: .compose, retry: { [weak self] in self?.recompose() }, operation: {
            try await self.compose(videoURL: videoURL)
        })
    }

    /// Pushes the project's mix levels onto the playing item without rebuilding anything.
    func applyMix() {
        guard let composed else { return }
        player?.currentItem?.audioMix = composed.audioMix(previewLevels(for: composed))
    }

    /// The project's mix, except that with nothing to duck under the original plays at full volume, so a
    /// freshly picked video sounds normal. Used by the preview only; the export takes the mix as set.
    private func previewLevels(for composed: ComposedVideo) -> MixLevels {
        var levels = project.mix
        if composed.trackKinds.values.allSatisfy({ $0 == .original }) { levels.original = 1 }
        return levels
    }

    /// Stops whatever is running. The user asked for it, so a job's partial result is dropped on purpose.
    func cancel() {
        composeTask?.cancel()
        composeTask = nil
        jobTask?.cancel()
        jobTask = nil
        activity = nil
        if needsRecompose {
            needsRecompose = false
            recompose()
        }
    }

    // MARK: - Private

    /// Runs one step in its slot and reports a failure with `retry`, which must re-enter the public method
    /// with values only (no captured operation), see `Failure.retry`.
    func run(
        _ activity: Activity,
        slot: Slot = .job,
        retry: (@MainActor () -> Void)? = nil,
        operation: @escaping () async throws -> Void
    ) {
        switch slot {
        case .compose: composeTask?.cancel()
        case .job: jobTask?.cancel()
        }
        self.activity = activity
        let task = Task {
            do {
                try await operation()
            } catch is CancellationError {
                // Cancelled or superseded; nothing to report.
            } catch {
                // AVFoundation and Photos report a cancelled task with their own errors; those are not failures.
                guard !Task.isCancelled else { return }
                let recovery = (error as? ElevenLabsError)?.recovery ?? .retry
                failure = Failure(message: error.localizedDescription, recovery: recovery, retry: retry)
            }
            if !Task.isCancelled { finish(slot) }
        }
        switch slot {
        case .compose: composeTask = task
        case .job: jobTask = task
        }
    }

    private func finish(_ slot: Slot) {
        activity = nil
        switch slot {
        case .compose:
            composeTask = nil
        case .job:
            jobTask = nil
            if needsRecompose {
                needsRecompose = false
                recompose()
            }
        }
    }

    /// Builds the edit and puts it on the player. Jobs call this directly at their end instead of
    /// `recompose()`, which would cancel the job that is still running them.
    func compose(videoURL: URL) async throws {
        let clips = voiceClips() + effectClips()
        let wasPlaying = player?.rate ?? 0 > 0
        let resumeAt = player?.currentTime()

        let composed = try await VideoComposer.compose(video: videoURL, clips: clips)
        try Task.checkCancellation()

        // No video composition for the preview: AVPlayer applies the track's preferredTransform itself and
        // captions are a SwiftUI overlay. The compositor is only needed for the export, and in the simulator
        // its frames can't be displayed by AVPlayerLayer at all (IQ-CA error -19230, black video).
        // AVPlayerItem is main-actor bound in iOS 26; creating it is cheap, loading happens asynchronously.
        let item = AVPlayerItem(asset: composed.asset)
        item.audioMix = composed.audioMix(previewLevels(for: composed))
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
}
