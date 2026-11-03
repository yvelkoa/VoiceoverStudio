import AVFoundation

/// The app's audio session. The category must be set explicitly: the system default obeys the silent switch,
/// so a freshly launched app would play the edit without any sound on a muted iPhone.
enum AudioSession {
    /// Category only, for launch. Activating here would stop whatever the user was listening to the moment the
    /// project list appears; AVPlayer activates the session itself when playback starts.
    static func configurePlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    /// Back to playback after a take, while the player is already in use.
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }
}
