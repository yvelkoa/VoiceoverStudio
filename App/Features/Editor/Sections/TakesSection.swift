import SwiftUI
import VoiceoverKit

/// Every take in timeline order, with who said it and when; swipe to delete.
struct TakesSection: View {
    let project: Project
    /// False while a swap or export runs: deleting a take then would have to throw that work away.
    var canEdit = true
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
                    if canEdit {
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(take) }
                    }
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
