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
