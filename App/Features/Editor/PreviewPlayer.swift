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
            VStack {
                Spacer()
                if let caption = captions.first(where: { $0.start <= currentTime && currentTime < $0.end }) {
                    Text(caption.text)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.8), radius: 3)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 56)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: currentTime)
            .allowsHitTesting(false)
        }
        .task(id: ObjectIdentifier(player)) {
            for await time in player.timeUpdates(every: 0.05) {
                currentTime = time
            }
        }
    }
}

private extension AVPlayer {
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
