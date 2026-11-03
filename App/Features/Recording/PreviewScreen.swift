import AVFoundation
import SwiftUI
import VoiceoverKit

/// Watch the current edit end to end with native transport controls and live captions.
struct PreviewScreen: View {
    let player: AVPlayer
    let captions: [Caption]
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
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear { player.pause() }
    }
}
