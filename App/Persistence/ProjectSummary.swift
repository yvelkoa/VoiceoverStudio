import Foundation
import VoiceoverKit

/// What the project list shows without loading a whole project.
nonisolated struct ProjectSummary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let videoDuration: Double
    let takeCount: Int
    let hasVideo: Bool
    let isExported: Bool
    let thumbnail: URL?
    /// False when the folder has a manifest that no longer decodes. Shown, not hidden: the media is still there.
    let isReadable: Bool

    init(document: ProjectDocument, folder: URL) {
        isReadable = true
        id = document.id
        title = document.title
        updatedAt = document.updatedAt
        videoDuration = document.videoDuration
        takeCount = document.takes.count
        hasVideo = document.videoFile != nil
        isExported = document.exportFile != nil
        let thumb = folder.appending(path: ProjectDocument.thumbnailName)
        thumbnail = FileManager.default.fileExists(atPath: thumb.path) ? thumb : nil
    }

    init(unreadableFolder folder: URL, id: UUID) {
        isReadable = false
        self.id = id
        title = "Unreadable project"
        updatedAt = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        videoDuration = 0
        takeCount = 0
        hasVideo = false
        isExported = false
        thumbnail = nil
    }
}
