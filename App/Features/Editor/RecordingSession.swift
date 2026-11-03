import AVFoundation
import Observation
import VoiceoverKit

/// One take from Record to Stop: who speaks, where on the timeline it started, the live level, and the
/// player's part in it (muted and playing while the microphone is open, stopped and rewound after).
///
/// Produces a `Finished` take for the owner to add to the project; it does not touch the project itself.
@Observable
final class RecordingSession {
    enum Failure: LocalizedError {
        case microphoneDenied

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Microphone access is off. Allow it in Settings to record takes."
            }
        }
    }

    /// What a stopped take amounts to; nil from `stop` means there was nothing worth keeping.
    struct Finished {
        let characterID: Character.ID
        let start: Double
        let duration: Double
        let recording: URL
    }

    private let recorder = TakeRecorder()
    private var characterID: Character.ID?
    private var start: Double = 0

    /// Record was pressed and the microphone permission is being asked; a second press must not start a
    /// second recorder.
    private(set) var isStarting = false

    var isRecording: Bool { recorder.isRecording }

    /// Called on the main actor when the system stops the recorder underneath us (call, Siri, headset gone).
    var onInterruption: (() -> Void)? {
        get { recorder.onInterruption }
        set { recorder.onInterruption = newValue }
    }

    /// The take in progress, for the timeline.
    var live: LiveRecording? {
        guard isRecording, let characterID else { return nil }
        return LiveRecording(characterID: characterID, start: start, waveform: Waveform(peaks: recorder.liveLevels))
    }

    /// Asks for the microphone if needed, then records into `folder` while `player` plays muted.
    /// Returns false when the owner's state moved on during the permission prompt (`stillValid`).
    @discardableResult
    func start(
        for characterID: Character.ID,
        player: AVPlayer,
        in folder: URL,
        stillValid: @MainActor () -> Bool
    ) async throws -> Bool {
        guard !isStarting, !isRecording else { return false }
        isStarting = true
        defer { isStarting = false }

        guard await recorder.requestPermission() else { throw Failure.microphoneDenied }
        // The permission prompt can take a while; the screen may have moved on meanwhile.
        guard stillValid() else { return false }

        self.characterID = characterID
        start = player.currentTime().seconds
        // The video is silenced while recording so the microphone doesn't pick it up.
        player.isMuted = true
        do {
            _ = try recorder.start(in: folder)
        } catch {
            player.isMuted = false
            throw error
        }
        player.play()
        return true
    }

    /// Stops the microphone and the player, rewinds to the take's start and returns the take, or nil (and
    /// deletes the file) when it is too short to be one.
    func stop(player: AVPlayer) -> Finished? {
        guard isRecording, let characterID else { return nil }
        player.rate = 0
        player.isMuted = false

        let duration = recorder.stop()
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        guard let url = recorder.lastRecordingURL else { return nil }
        guard duration >= TakeResolver.minimumDuration else {
            // Too short to be a take; the file would otherwise sit in the project folder (and its backup) forever.
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return Finished(characterID: characterID, start: start, duration: duration, recording: url)
    }
}
