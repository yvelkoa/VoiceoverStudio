import Foundation
import VoiceoverKit

/// What a project looks like on disk: `project.json` next to its media files.
/// Files are referenced by name, never by absolute path: iOS moves the app container between launches.
nonisolated struct ProjectDocument: Codable {
    static let fileName = "project.json"
    static let thumbnailName = "thumbnail.jpg"

    struct TakeRecord: Codable {
        var id: UUID
        var characterID: UUID
        var start: Double
        var duration: Double
        var file: String
        var sequence: Int
    }

    struct EffectRecord: Codable {
        var id: UUID
        var prompt: String
        var start: Double
        var duration: Double
        var file: String
    }

    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    var videoFile: String?
    var videoDuration: Double

    var mode: EditingMode
    var characters: [Character]
    var activeCharacterID: UUID?
    var takes: [TakeRecord]
    var nextSequence: Int
    /// Keyed by take id string, for readable JSON.
    var transcripts: [String: [TimedWord]]
    var convertedAudio: [String: String]
    var conversionDrift: [String: Double]
    var effects: [EffectRecord]

    var mix: MixLevels
    var trimStart: Double?
    var trimEnd: Double?

    var script: String
    var voice: Voice?
    var speechFile: String?
    var typeCaptions: [Caption]

    var exportFile: String?
}

/// Record takes with the microphone, or type a script for ElevenLabs to read.
nonisolated enum EditingMode: String, Codable, Hashable {
    case record, type
}

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
