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
