import SwiftUI
import VoiceoverKit

/// Every generated sound on the effects lane, in timeline order; swipe to delete.
struct EffectsSection: View {
    let model: EditorModel

    var body: some View {
        Section("Effects") {
            let effects = model.project.effects.sorted { $0.start < $1.start }

            if effects.isEmpty {
                Text("No effects yet. Ask for ideas here, or add one at the playhead in the recorder.")
                    .foregroundStyle(.secondary)
            }

            ForEach(effects) { effect in
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(TimelineStrip.effectColor)
                    Text(effect.prompt)
                        .lineLimit(2)
                    Spacer()
                    Text("\(timecode(effect.start)) – \(timecode(effect.end))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    if !model.isBusy {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.remove(effect) }
                    }
                }
            }
        }
    }

    private func timecode(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }
}
