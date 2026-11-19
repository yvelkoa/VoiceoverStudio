import SwiftUI
import VoiceoverKit

/// Who speaks: one row per character, tap to make active, navigate to pick a voice.
/// Edits go through the model so the composition and captions follow (see `EditorModel.update(_:)`).
struct CharactersSection: View {
    let model: EditorModel

    private var project: Project { model.project }

    var body: some View {
        Section {
            ForEach(project.characters) { character in
                CharacterRow(model: model, character: character)
            }
            .onDelete { offsets in
                for index in offsets { model.removeCharacter(project.characters[index].id) }
            }
            // The last character stays: takes need someone to belong to.
            .deleteDisabled(project.characters.count == 1 || model.isBusy)
            Button("Add character", systemImage: "person.badge.plus") { model.addCharacter() }
        } header: {
            Text("Characters")
        } footer: {
            Text("Record each character separately. The active one gets the next take.")
        }
    }
}

private struct CharacterRow: View {
    let model: EditorModel
    let character: Character

    private var project: Project { model.project }

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
            NavigationLink(value: EditorRoute.voice(.character(character.id))) {
                Text(character.voice?.name ?? String(localized: "Voice"))
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
                model.update(updated)
            }
        )
    }
}
