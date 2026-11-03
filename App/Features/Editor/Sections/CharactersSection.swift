import SwiftUI
import VoiceoverKit

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
                .frame(maxWidth: .infinity)

            // The voice name can be long ("Adam - Dominant, Firm"); it yields to the name field and truncates.
            NavigationLink {
                VoicePickerView(client: client, selection: voiceBinding)
            } label: {
                Text(character.voice?.name ?? "Voice")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(character.voice == nil ? .secondary : .primary)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(-1)
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
