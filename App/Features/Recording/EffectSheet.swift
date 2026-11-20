import AVFoundation
import SwiftUI
import VoiceoverKit

/// Describe a sound; ElevenLabs generates it once and it lands on the effects lane at the playhead.
struct EffectSheet: View {
    let start: Double
    let onGenerate: (String, Double?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var seconds: Double = 0

    private let choices: [Double] = [0, 1, 2, 3, 5, 8, 12]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. dog barks twice, close", text: $prompt, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("Placed at \(start.formatted(.number.precision(.fractionLength(1)))) s. Each generation costs credits.")
                }
                Section("Length") {
                    Picker("Length", selection: $seconds) {
                        ForEach(choices, id: \.self) { choice in
                            Text(choice == 0 ? "Auto" : "\(Int(choice)) s")
                                .tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Sound effect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        onGenerate(prompt, seconds == 0 ? nil : seconds)
                        dismiss()
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
