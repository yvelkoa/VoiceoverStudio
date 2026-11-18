import SwiftUI

/// Background music: describe it and ElevenLabs composes an instrumental track as long as the video.
struct MusicSection: View {
    let model: EditorModel
    @State private var prompt = ""

    var body: some View {
        Section {
            if let music = model.project.music {
                LabeledContent {
                    Text(Duration.seconds(music.duration).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                } label: {
                    Label(music.prompt, systemImage: "music.note")
                        .lineLimit(2)
                }
            }
            TextField("e.g. calm lo-fi piano, slow", text: $prompt, axis: .vertical)
                .lineLimit(1...3)
            Button(generateTitle, systemImage: "wand.and.stars") {
                model.generateMusic(prompt: prompt)
            }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.activity != nil)
            if model.project.music != nil {
                Button("Remove music", systemImage: "trash", role: .destructive) { model.removeMusic() }
                    .disabled(model.isBusy)
            }
        } header: {
            Text("Music")
        } footer: {
            Text("Instrumental, as long as the video. Each generation costs credits.")
        }
        .onAppear {
            if prompt.isEmpty, let music = model.project.music { prompt = music.prompt }
        }
    }

    private var generateTitle: LocalizedStringKey {
        model.project.music == nil ? "Generate music" : "Replace music"
    }
}
