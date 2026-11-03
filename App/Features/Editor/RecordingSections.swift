import SwiftUI
import VoiceoverKit

/// Palette for characters on the timeline and in captions.
enum CharacterPalette {
    static let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal]

    static func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}

/// Who speaks: one row per character, tap to make active, navigate to pick a voice.
struct CharactersSection: View {
    @Bindable var project: Project
    let client: ElevenLabsClient

    var body: some View {
        Section {
            ForEach(project.characters) { character in
                CharacterRow(project: project, character: character, client: client)
            }
            .onDelete { offsets in
                for index in offsets { project.removeCharacter(project.characters[index].id) }
            }
            Button("Add character", systemImage: "person.badge.plus") {
                project.addCharacter(named: "Character \(project.characters.count + 1)")
            }
        } header: {
            Text("Characters")
        } footer: {
            Text("Record each character separately. The active one gets the next take.")
        }
    }
}

private struct CharacterRow: View {
    @Bindable var project: Project
    let character: Character
    let client: ElevenLabsClient

    var body: some View {
        HStack(spacing: 12) {
            Button {
                project.activeCharacterID = character.id
            } label: {
                Image(systemName: project.activeCharacterID == character.id ? "record.circle.fill" : "circle")
                    .foregroundStyle(CharacterPalette.color(character.colorIndex))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project.activeCharacterID == character.id ? "Active" : "Make active")

            TextField("Name", text: nameBinding)

            NavigationLink {
                VoicePickerView(client: client, selection: voiceBinding)
            } label: {
                Text(character.voice?.name ?? "Voice")
                    .foregroundStyle(character.voice == nil ? .secondary : .primary)
            }
            .fixedSize()
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { project.character(character.id)?.name ?? "" },
            set: { name in
                guard var updated = project.character(character.id) else { return }
                updated.name = name
                project.update(updated)
            }
        )
    }

    private var voiceBinding: Binding<Voice?> {
        Binding(
            get: { project.character(character.id)?.voice },
            set: { voice in
                guard var updated = project.character(character.id) else { return }
                updated.voice = voice
                project.update(updated)
            }
        )
    }
}

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
    let title: String
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

/// Every take in timeline order, with who said it and when; swipe to delete.
struct TakesSection: View {
    let project: Project
    let onDelete: (Take) -> Void

    var body: some View {
        Section {
            let takes = project.takes.sorted { ($0.start, $0.sequence) < ($1.start, $1.sequence) }
            if takes.isEmpty {
                Text("No takes yet. Move the playhead, then press Record and speak over the video.")
                    .foregroundStyle(.secondary)
            }
            ForEach(takes) { take in
                let character = project.character(take.characterID)
                HStack {
                    Circle()
                        .fill(CharacterPalette.color(character?.colorIndex ?? 0))
                        .frame(width: 10, height: 10)
                    Text(character?.name ?? "Unknown")
                    Spacer()
                    Text("\(timecode(take.start)) – \(timecode(take.end))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if project.convertedAudio[take.id] != nil {
                        let drift = project.conversionDrift[take.id] ?? 0
                        if abs(drift) > 0.15 {
                            let seconds = drift.formatted(.number.precision(.fractionLength(1)))
                            Image(systemName: "waveform.badge.exclamationmark")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Voice swapped, timing off by \(seconds) seconds")
                        } else {
                            Image(systemName: "waveform.badge.checkmark")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Voice swapped")
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(take) }
                }
            }
        } header: {
            Text("Takes")
        } footer: {
            if project.conversionDrift.values.contains(where: { abs($0) > 0.15 }) {
                Text("An orange mark means the swapped voice came back a different length, so captions may drift there.")
            }
        }
    }

    private func timecode(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }
}
