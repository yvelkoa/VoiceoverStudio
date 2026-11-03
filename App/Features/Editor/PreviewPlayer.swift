import AVKit
import SwiftUI
import VoiceoverKit

/// Plays the composed edit with captions drawn by SwiftUI.
/// The export burns captions in with Core Animation, but `AVVideoCompositionCoreAnimationTool`
/// only works offline, so the preview mirrors the same timing with an overlay instead.
struct PreviewPlayer: View {
    let player: AVPlayer
    let captions: [Caption]

    @State private var currentTime: Double = 0

    var body: some View {
        VideoPlayer(player: player) {
            CaptionOverlay(captions: captions, currentTime: currentTime)
        }
        .task(id: ObjectIdentifier(player)) {
            for await time in player.timeUpdates(every: 0.05) {
                currentTime = time
            }
        }
    }
}

/// The captions visible at `currentTime`, one line per speaker, ordered by track.
struct CaptionOverlay: View {
    let captions: [Caption]
    let currentTime: Double

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            let visible = captions
                .filter { $0.start <= currentTime && currentTime < $0.end }
                .sorted { $0.track < $1.track }
            ForEach(visible) { caption in
                Text(caption.text)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.8), radius: 3)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
            Color.clear.frame(height: 56)
        }
        .animation(.easeOut(duration: 0.12), value: currentTime)
        .allowsHitTesting(false)
    }
}

extension AVPlayer {
    /// Periodic playback time as an async sequence; the observer is removed when iteration stops.
    func timeUpdates(every seconds: Double) -> AsyncStream<Double> {
        AsyncStream { continuation in
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
