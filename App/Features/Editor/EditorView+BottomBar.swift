import SwiftUI
import VoiceoverKit

// The bar under the form: the running job with Cancel, or the mode's primary action.
extension EditorView {

    var primaryButton: some View {
        Group {
            // Recording happens only in the full-screen recorder, so this bar never needs a Stop button.
            if let activity = model.activity {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(activityTitle(activity))
                        .lineLimit(1)
                    Spacer()
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
                .padding(.horizontal, 4)
            } else {
                switch model.mode {
                case .record:
                    HStack(spacing: 12) {
                        Button {
                            cover = .recorder
                        } label: {
                            Label(recordTitle, systemImage: "record.circle")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(model.player == nil)

                        if model.canSwapVoices {
                            Button {
                                model.swapVoices()
                            } label: {
                                // Its own width, never wrapped: Record gives way instead.
                                Label(swapTitle, systemImage: "arrow.triangle.2.circlepath")
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!app.hasAPIKey)
                        }
                    }
                    .controlSize(.large)
                case .type:
                    Button {
                        model.generate()
                    } label: {
                        Label(model.hasResult ? "Regenerate" : "Generate voiceover", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canGenerate || !app.hasAPIKey)
                }
            }
        }

        // One height whatever the bar shows, so the form above doesn't jump when a job starts or ends.
        .frame(height: 52)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Shows what a swap will cost: ElevenLabs bills speech-to-speech by audio length.
    private var swapTitle: String {
        let seconds = Int(model.project.secondsNeedingConversion.rounded(.up))
        return String(localized: "Swap voices · \(seconds) s")
    }

    private var recordTitle: String {
        model.project.takes.isEmpty ? String(localized: "Record takes") : String(localized: "Record more")
    }

    private func activityTitle(_ activity: EditorModel.Activity) -> String {
        switch activity {
        case .generating:
            String(localized: "Generating voice…")
        case .generatingEffect:
            String(localized: "Generating sound effect…")
        case .generatingEffects:
            String(localized: "Generating sound effects…")
        case .generatingMusic:
            String(localized: "Composing music…")
        case .composing:
            String(localized: "Updating preview…")
        case .exporting:
            String(localized: "Exporting…")
        case .swapping:
            String(localized: "Swapping voices…")
        case .saving:
            String(localized: "Saving to Photos…")
        }
    }
}
