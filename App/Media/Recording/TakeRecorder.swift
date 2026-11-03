import AVFoundation
import Observation

/// Records the microphone into an AAC file in the given directory (the project folder).
///
/// A phone call, Siri, or an unplugged headset stops the system's recorder underneath us; `onInterruption`
/// lets the owner end the take properly (keeping what was recorded) instead of showing REC over a dead recorder.
@Observable
final class TakeRecorder {
    enum Failure: LocalizedError {
        case microphoneDenied, alreadyRecording

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Microphone access is off. Allow it in Settings to record takes."
            case .alreadyRecording: "A take is already being recorded."
            }
        }
    }

    private(set) var isRecording = false
    /// The file written by the most recent `start()`.
    private(set) var lastRecordingURL: URL?
    /// Input level so far in this take, one value per `Waveform.bucket`, 0...1. Drawn live on the timeline.
    private(set) var liveLevels: [Float] = []
    private var recorder: AVAudioRecorder?
    private var metering: Task<Void, Never>?
    private var sessionObservers: [any NSObjectProtocol] = []

    /// Called on the main actor when the session is interrupted or the input route goes away mid-take.
    var onInterruption: (() -> Void)?

    /// Asks for microphone access the first time; afterwards returns the stored answer.
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Starts a new file and returns its URL. The session is configured so playback keeps working.
    func start(in directory: URL) throws -> URL {
        guard recorder == nil else { throw Failure.alreadyRecording }
        try AudioSession.activateRecording()

        let url = directory.appending(path: "take-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        lastRecordingURL = url
        liveLevels = []
        isRecording = true
        startMetering()
        observeSession()
        return url
    }

    /// Stops and returns the recorded length in seconds.
    func stop() -> Double {
        metering?.cancel()
        metering = nil
        stopObservingSession()
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        AudioSession.activatePlayback()
        return duration
    }

    /// Interruptions (`.began`) and a vanished input (`.oldDeviceUnavailable`) end the take. The notification
    /// closures are nonisolated, so only a plain value is taken from them before hopping to the main actor.
    private func observeSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        sessionObservers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor [weak self] in self?.interrupted() }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { note in
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                Task { @MainActor [weak self] in self?.interrupted() }
            },
        ]
    }

    private func stopObservingSession() {
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
        sessionObservers = []
    }

    private func interrupted() {
        guard isRecording else { return }
        onInterruption?()
    }

    /// Samples the peak level on the waveform's grid. The array is filled up to the recorder's own clock,
    /// so the live trace stays aligned with the playhead even when the timer runs late.
    private func startMetering() {
        metering = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Waveform.bucket))
                guard let self, let recorder else { return }
                recorder.updateMeters()
                let level = Waveform.level(fromDecibels: recorder.peakPower(forChannel: 0))
                let expected = Int(recorder.currentTime / Waveform.bucket)
                while liveLevels.count < expected { liveLevels.append(level) }
            }
        }
    }
}
