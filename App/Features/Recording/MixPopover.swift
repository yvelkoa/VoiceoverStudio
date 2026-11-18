import AVFoundation
import SwiftUI
import VoiceoverKit

/// Levels for the four kinds of audio; changes reach the player immediately.
struct MixPopover: View {
    @Bindable var project: Project
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MixSliders(mix: $project.mix, onChange: onChange)
        }
        .padding()
        .frame(minWidth: 280)
        .presentationCompactAdaptation(.popover)
    }
}
