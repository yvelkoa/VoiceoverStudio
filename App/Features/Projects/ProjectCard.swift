import SwiftUI

/// A project in the grid: its poster frame first, since that is how a video is recognised.
struct ProjectCard: View {
    let summary: ProjectSummary
    @State private var image: UIImage?

    private static let corner: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 4)
        }
        .task(id: summary.thumbnail) {
            // UIImage decodes lazily at draw time; byPreparingForDisplay does it here, off the main thread.
            guard let path = summary.thumbnail?.path else { return }

            image = await UIImage(contentsOfFile: path)?.byPreparingForDisplay()
        }
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if !summary.isReadable {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                } else {
                    WaveformMark()
                        .frame(width: 64, height: 30)
                        .foregroundStyle(.tint.opacity(0.6))
                }
            }
            .background(.tint.opacity(0.1))
            .clipShape(.rect(cornerRadius: Self.corner))
            .overlay(alignment: .bottomLeading) {
                if summary.hasVideo {
                    badge {
                        Text(verbatim: Duration.seconds(summary.videoDuration).formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if summary.isExported {
                    badge {
                        Label("exported", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .contentShape(.rect(cornerRadius: Self.corner))
    }

    private func badge(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: .capsule)
            .padding(8)
    }

    private var details: String {
        guard summary.isReadable else {
            return String(localized: "Couldn't read this project's manifest. Its files are still on disk.")
        }

        let updated = summary.updatedAt.formatted(.relative(presentation: .named))
        guard summary.hasVideo else { return [String(localized: "No video yet"), updated].joined(separator: " · ") }

        return [String(localized: "\(summary.takeCount) takes"), updated].joined(separator: " · ")
    }
}
