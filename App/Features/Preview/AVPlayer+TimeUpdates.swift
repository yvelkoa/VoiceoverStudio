import AVKit
import SwiftUI
import VoiceoverKit

extension AVPlayer {
    /// Periodic playback time as an async sequence; the observer is removed when iteration stops.
    /// Only the newest time is kept: a stale one is worthless, and a slow consumer must not pile them up.
    func timeUpdates(every seconds: Double) -> AsyncStream<Double> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // The observer token is an opaque `Any`; it is only ever handed back to AVPlayer on the main actor.
            nonisolated(unsafe) let token = addPeriodicTimeObserver(
                forInterval: CMTime(seconds: seconds, preferredTimescale: 600),
                queue: .main
            ) { time in
                continuation.yield(time.seconds)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeTimeObserver(token) }
            }
        }
    }
}
