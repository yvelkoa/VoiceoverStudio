import SwiftUI

struct ProjectRow: View {
    let summary: ProjectSummary
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
                }
            }
            .task(id: summary.thumbnail) {
                // Decoded off the main thread so a long list scrolls without hitches.
                guard let path = summary.thumbnail?.path else { return }
                image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: path) }.value
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
        guard summary.hasVideo else { return "No video yet" }
        var parts = [Duration.seconds(summary.videoDuration).formatted(.time(pattern: .minuteSecond))]
        parts.append("\(summary.takeCount) \(summary.takeCount == 1 ? "take" : "takes")")
        if summary.isExported { parts.append("exported") }
        return parts.joined(separator: " · ")
    }
}
