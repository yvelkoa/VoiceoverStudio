import AVFoundation
import Observation

/// Records the microphone into an AAC file in the temporary directory.
@Observable
final class TakeRecorder {
    enum Failure: LocalizedError {
        case microphoneDenied

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Microphone access is off. Allow it in Settings to record takes."
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

    /// Asks for microphone access the first time; afterwards returns the stored answer.
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Starts a new file and returns its URL. The session is configured so playback keeps working.
    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = URL.temporaryDirectory.appending(path: "take-\(UUID().uuidString).m4a")
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
        return url
    }

    /// Stops and returns the recorded length in seconds.
    func stop() -> Double {
        metering?.cancel()
        metering = nil
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        return duration
    }

    /// Samples the peak level on the waveform's grid so the live trace matches the stored one.
    private func startMetering() {
        metering = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Waveform.bucket))
                guard let self, let recorder else { return }
                recorder.updateMeters()
                // Peak power is in dBFS; -50 dB and below reads as silence, 0 dB is full scale.
                let decibels = recorder.peakPower(forChannel: 0)
                liveLevels.append(max(0, min(1, (decibels + 50) / 50)))
            }
        }
    }
}
