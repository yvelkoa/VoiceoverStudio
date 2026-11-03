import AVFoundation
import SwiftUI
import VoiceoverKit

/// Watch the current edit end to end with native transport controls and live captions.
struct PreviewScreen: View {
    let player: AVPlayer
    let captions: [Caption]
    /// The export range; playback is confined to it so the preview shows exactly what will be exported.
    var range: ClosedRange<Double>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PreviewPlayer(player: player, captions: captions)
                .ignoresSafeArea(edges: .bottom)
                .background(.black)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear {
            let start = CMTime(seconds: range?.lowerBound ?? 0, preferredTimescale: 600)
            if let range {
                player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: range.upperBound, preferredTimescale: 600)
            }
            player.seek(to: start)
            player.play()
        }
        .onDisappear {
            player.pause()
            player.currentItem?.forwardPlaybackEndTime = .invalid
        }
    }
}
