import SwiftUI

struct ProjectRow: View {
    let summary: ProjectSummary
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if !summary.isReadable {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                } else {
                    Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
                }
            }
            .task(id: summary.thumbnail) {
                // UIImage decodes lazily at draw time; byPreparingForDisplay does it here, off the main thread.
                guard let path = summary.thumbnail?.path else { return }
                image = await UIImage(contentsOfFile: path)?.byPreparingForDisplay()
            }
            .frame(width: 54, height: 72)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title).font(.headline)
                Text(details).font(.subheadline).foregroundStyle(.secondary)
                Text(summary.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        guard summary.isReadable else {
            return String(localized: "Couldn't read this project's manifest. Its files are still on disk.")
        }
        guard summary.hasVideo else { return String(localized: "No video yet") }
        var parts = [Duration.seconds(summary.videoDuration).formatted(.time(pattern: .minuteSecond))]
        parts.append(String(localized: "\(summary.takeCount) takes"))
        if summary.isExported { parts.append(String(localized: "exported")) }
        return parts.joined(separator: " · ")
    }
}
