import AVFoundation
import Foundation
import Observation
import VoiceoverKit

/// Coordinates one open project. `Project` holds the state; four owned objects do the work (`WorkRunner`
/// runs steps, `EditPlayer` plays the edit, `RecordingSession` records a take, `TranscriptionQueue` recognises
/// it); this type decides *what happens when*: which clips make the edit, and when to rebuild, swap or export.
/// Record mode lives in `+Recording`, the effects lane in `+Effects`, background music in `+Music`, sounds
/// suggested by the on-device model in `+SoundIdeas`, the credit-spending steps in `+Jobs`.
@Observable
final class EditorModel {
    typealias Mode = EditingMode

    typealias Activity = WorkRunner.Activity
    typealias Failure = WorkRunner.Failure

    // MARK: - Dependencies

    let project: Project
    let client: ElevenLabsClient
    /// Media and system work: composing, export, Photos, transcription, waveforms. See `EditorServices`.
    let services: EditorServices
    /// One take at a time, from Record to Stop, including the player's part in it.
    let recording = RecordingSession()
    /// Runs every step in its slot (compose vs. job) and holds the activity and failure the UI shows.
    private let work = WorkRunner()
    /// Owns the AVPlayer and the composed edit; the model only decides when and from which clips to rebuild.
    let edit: EditPlayer
    /// One recogniser task per take; words come back through `onWords`.
    let transcriptions: TranscriptionQueue
    /// Sound effects and music suggested by the on-device model; see `+SoundIdeas`.
    let soundIdeas: SoundIdeas
    private var autosaver: ProjectAutosaver?

    // MARK: - Project-backed state (stored on the project so it survives relaunch)

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

    var script: String {
        get { project.script }
        set { project.script = newValue }
    }

    var voice: Voice? {
        get { project.voice }
        set { project.voice = newValue }
    }

    var videoURL: URL? { project.videoURL }
    var videoDuration: Double { project.videoDuration }
    var speechFile: URL? { project.speechFile }
    var exportedURL: URL? { project.exportedURL }
    var trimmedScript: String { script.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The part of the video an export covers, or nil for all of it. The preview plays the same range.
    var exportRange: ClosedRange<Double>? { project.isTrimmed ? project.trimRange : nil }

    // MARK: - Output (written by the model and its extensions; views only read it)

    var captions: [Caption] = []
    var player: AVPlayer? { edit.player }
    var composed: ComposedVideo? { edit.composed }
    /// The current export has been added to the photo library.
    var savedToPhotos = false
    /// Thumbnails for the scrubber, decoded once per video; decoding 60 fps frames on every open stuttered.
    private(set) var frameStrip: CGImage?

    // MARK: - Activity and failure (forwarded from the runner so views keep one object to read)

    var activity: Activity? { work.activity }

    var failure: Failure? {
        get { work.failure }
        set { work.failure = newValue }
    }

    /// A swap, export, generation or save is running; see `WorkRunner.isBusy`.
    var isBusy: Bool { work.isBusy }

    // MARK: - Decorations in flight

    private var frameStripTask: Task<Void, Never>?
    /// Waveform decodes for the takes and effects of a loaded project; cancelled with the editor.
    private var waveformTask: Task<Void, Never>?

    // MARK: - Lifetime

    init(project: Project, client: ElevenLabsClient, store: ProjectStore?, services: EditorServices = .live) {
        self.project = project
        self.client = client
        self.services = services
        edit = EditPlayer(compose: services.compose)
        transcriptions = TranscriptionQueue(services: services)
        soundIdeas = SoundIdeas(services: services)
        if let store { autosaver = ProjectAutosaver(project: project, store: store) }

        // A call or an unplugged headset ends the take the same way Stop does, keeping what was recorded.
        recording.onInterruption = { [weak self] in self?.stopRecording() }
        // The video ran out: keep the take, as if Stop had been pressed at the last frame.
        recording.onVideoEnd = { [weak self] in self?.stopRecording() }
        transcriptions.onWords = { [weak self] takeID, words in
            guard let self else { return }
            project.setTranscript(words, for: takeID)
            rebuildCaptions()
        }
        transcriptions.onFailure = { [weak self] take, error in
            self?.failure = Failure(message: error.localizedDescription, recovery: .retry) { [weak self] in
                self?.transcriptions.transcribe(take)
            }
        }

        restore()
    }

    /// The editor is gone when the screen that owned it is popped: flush the last changes and stop playback.
    /// (Not onDisappear: that also fires when a picker is pushed on top, and must not cancel an export.)
    isolated deinit {
        work.cancelAll()
        frameStripTask?.cancel()
        waveformTask?.cancel()
        transcriptions.cancelAll()
        soundIdeas.cancel()

        edit.pause()
        autosaver?.stop()
    }

    /// Brings a loaded project back to life: captions, the player, then the waveforms.
    private func restore() {
        switch mode {
        case .record: rebuildCaptions()
        case .type: captions = project.typeCaptions
        }
        recompose()

        let sources = project.takes.map { ($0.id, $0.recording) } + project.effects.map { ($0.id, $0.audio) }
            + (project.music.map { [($0.id, $0.audio)] } ?? [])
        let waveform = services.waveform
        waveformTask = Task(priority: .utility) { [project] in
            await withTaskGroup { group in
                for (id, url) in sources {
                    group.addTask { try? await waveform(url) }
                    // One at a time keeps the decoder from competing with the player that just started.
                    if let waveform = await group.next(), let waveform { project.setWaveform(waveform, for: id) }
                }
            }
        }
    }

    // MARK: - What the UI may do right now

    var isRecording: Bool { recording.isRecording }

    var canGenerate: Bool {
        videoURL != nil && voice != nil && !trimmedScript.isEmpty && activity == nil
    }

    var canRecord: Bool {
        player != nil && project.activeCharacter != nil && activity == nil && !recording.isStarting && !isRecording
    }

    var canSwapVoices: Bool {
        mode == .record && !project.takesNeedingConversion.isEmpty && activity == nil && !isRecording
    }

    /// Something worth exporting: generated speech in Type mode, at least one take in Record mode.
    var hasResult: Bool {
        switch mode {
        case .type: speechFile != nil
        case .record: !project.takes.isEmpty
        }
    }

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
            failure = Failure(message: String(localized: "Couldn't store this video."), recovery: .none)
            return
        }

        let duration = (try? await services.duration(destination)) ?? 0
        project.setVideo(destination, duration: duration)
        recompose()

        let thumbnail = project.folder.appending(path: ProjectDocument.thumbnailName)
        Task { [services] in try? await services.writeThumbnail(destination, thumbnail) }
    }

    // MARK: - The edit

    /// Re-builds the edit after something moved; no network involved. Deferred while a job runs.
    func recompose() {
        guard let videoURL else { return }
        work.whenIdle { [weak self] in
            guard let self else { return }
            run(.composing, slot: .compose, retry: { [weak self] in self?.recompose() }, operation: {
                try await self.compose(videoURL: videoURL)
            })
        }
    }

    /// Builds the edit and puts it on the player. Jobs call this directly at their end instead of
    /// `recompose()`, which would cancel the job that is still running them.
    func compose(videoURL: URL) async throws {
        try await edit.compose(video: videoURL, clips: voiceClips() + effectClips() + musicClips(), mix: project.mix)

        // What was exported no longer matches what is heard.
        project.clearExport()
        savedToPhotos = false
    }

    /// Pushes the project's mix levels onto the playing item without rebuilding anything.
    func applyMix() {
        edit.applyMix(project.mix)
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

    /// From the start of the export range, so a trimmed export opens on the track's first bar; the composer
    /// cuts it at the video's end.
    private func musicClips() -> [AudioClip] {
        project.music.map { [AudioClip(url: $0.audio, kind: .music, start: project.musicStart)] } ?? []
    }

    // MARK: - Running steps

    /// See `WorkRunner.run`. Kept on the model so the extensions read as before.
    func run(
        _ activity: Activity,
        slot: WorkRunner.Slot = .job,
        retry: (@MainActor () -> Void)? = nil,
        operation: @escaping () async throws -> Void
    ) {
        work.run(activity, slot: slot, retry: retry, operation: operation)
    }

    /// Stops whatever is running; the user asked for it.
    func cancel() {
        work.cancelAll()
    }
}
