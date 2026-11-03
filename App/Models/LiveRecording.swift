import AVFoundation
import Foundation
import VoiceoverKit

/// A take in progress: who is speaking, from where on the timeline, and the input level so far.
struct LiveRecording {
    let characterID: Character.ID
    let start: Double
    let waveform: Waveform
}
