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

    init(document: ProjectDocument, folder: URL) {
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
}
