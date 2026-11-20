import AVKit
import SwiftUI
import VoiceoverKit

/// The captions visible at `currentTime`, one line per speaker, ordered by track.
struct CaptionOverlay: View {
    let captions: [Caption]
    let currentTime: Double
    /// Smaller type and margins for the editor's stage, where the picture is a third of the screen.
    var compact = false

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            let visible = captions
                .filter { $0.start <= currentTime && currentTime < $0.end }
                .sorted { $0.track < $1.track }
            ForEach(visible) { caption in
                Text(caption.text)
                    .font(compact ? .subheadline.bold() : .title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.8), radius: 3)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
            Color.clear.frame(height: compact ? 14 : 56)
        }
        .animation(.easeOut(duration: 0.12), value: currentTime)
        .allowsHitTesting(false)
    }
}
