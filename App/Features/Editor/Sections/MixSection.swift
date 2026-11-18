import SwiftUI
import VoiceoverKit

/// Levels of the original soundtrack, the voice and the effects. Applied live to the player and to the export.
struct MixSection: View {
    @Bindable var project: Project
    let onChange: () -> Void

    var body: some View {
        Section {
            MixSliders(mix: $project.mix, onChange: onChange)
        } header: {
            Text("Mix")
        } footer: {
            Text("The same levels go into the exported video.")
        }
    }
}

struct MixSliders: View {
    @Binding var mix: MixLevels
    let onChange: () -> Void

    var body: some View {
        VolumeRow(title: "Original audio", systemImage: "speaker.wave.2", value: $mix.original, onChange: onChange)
        VolumeRow(title: "Voice", systemImage: "person.wave.2", value: $mix.voice, onChange: onChange)
        VolumeRow(title: "Effects", systemImage: "sparkles", value: $mix.effect, onChange: onChange)
    }
}

private struct VolumeRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var value: Float
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Label(title, systemImage: systemImage)
            }
            Slider(value: $value, in: 0...1)
                .onChange(of: value) { _, _ in onChange() }
        }
    }
}
