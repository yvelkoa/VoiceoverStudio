import AVFoundation
import SwiftUI
import VoiceoverKit

struct VoicePickerView: View {
    let client: ElevenLabsClient
    @Binding var selection: Voice?

    @Environment(\.dismiss) private var dismiss
    @State private var voices: [Voice] = []
    @State private var error: String?
    @State private var previewPlayer: AVPlayer?
    @State private var previewingID: Voice.ID?

    var body: some View {
        List(voices) { voice in
            HStack {
                Button {
                    selection = voice
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name).font(.body.weight(.medium))
                        if !voice.summary.isEmpty {
                            Text(voice.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if voice.id == selection?.id {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
                if voice.previewURL != nil {
                    Button {
                        togglePreview(voice)
                    } label: {
                        Image(systemName: previewingID == voice.id ? "stop.circle.fill" : "play.circle")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(previewingID == voice.id ? "Stop preview" : "Play preview of \(voice.name)")
                }
            }
        }
        .overlay {
            if voices.isEmpty && error == nil {
                ProgressView()
            } else if let error {
                ContentUnavailableView("Couldn't load voices", systemImage: "waveform.slash", description: Text(error))
            }
        }
        .navigationTitle("Voice")
        .task { await load() }
        .refreshable { await load(force: true) }
        .onDisappear { previewPlayer?.pause() }
    }

    private func load(force: Bool = false) async {
        do {
            voices = try await client.voices(forceRefresh: force)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func togglePreview(_ voice: Voice) {
        previewPlayer?.pause()
        guard previewingID != voice.id, let url = voice.previewURL else {
            previewingID = nil
            return
        }
        let player = AVPlayer(url: url)
        player.play()
        previewPlayer = player
        previewingID = voice.id
    }
}
