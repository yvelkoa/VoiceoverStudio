import SwiftUI
import VoiceoverKit

/// Palette for characters on the timeline and in captions.
enum CharacterPalette {
    static let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal]

    static func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}
