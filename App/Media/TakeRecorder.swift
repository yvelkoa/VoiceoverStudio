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
    private var recorder: AVAudioRecorder?

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
        recorder.record()
        self.recorder = recorder
        lastRecordingURL = url
        isRecording = true
        return url
    }

    /// Stops and returns the recorded length in seconds.
    func stop() -> Double {
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        return duration
    }
}
