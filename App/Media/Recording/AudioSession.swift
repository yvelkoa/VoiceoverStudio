import AVFoundation

/// The app's audio session. Playback must be set explicitly: the system default obeys the silent switch,
/// so a freshly launched app would play the edit without any sound on a muted iPhone.
enum AudioSession {
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
