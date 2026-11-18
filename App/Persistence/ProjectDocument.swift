import Foundation
import VoiceoverKit

/// What a project looks like on disk: `project.json` next to its media files.
/// Files are referenced by name, never by absolute path: iOS moves the app container between launches.
nonisolated struct ProjectDocument: Codable {
    static let fileName = "project.json"
    static let thumbnailName = "thumbnail.jpg"
    /// Bump when a change cannot be expressed as a new optional field. Decoding reads it through
    /// `decodeIfPresent`, so manifests written before the field existed count as version 1.
    static let currentVersion = 1

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

    struct MusicRecord: Codable {
        var id: UUID
        var prompt: String
        var duration: Double
        var file: String
    }

    var version = currentVersion
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
    var music: MusicRecord?

    var mix: MixLevels
    var trimStart: Double?
    var trimEnd: Double?

    var script: String
    var voice: Voice?
    var speechFile: String?
    var typeCaptions: [Caption]

    var exportFile: String?
}

/// Hand-written so that fields added later can default instead of failing the whole manifest. A project the
/// list cannot decode looks deleted to the user; every new field must be `decodeIfPresent` with a default.
nonisolated extension ProjectDocument {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        videoFile = try c.decodeIfPresent(String.self, forKey: .videoFile)
        videoDuration = try c.decodeIfPresent(Double.self, forKey: .videoDuration) ?? 0
        mode = try c.decodeIfPresent(EditingMode.self, forKey: .mode) ?? .record
        characters = try c.decodeIfPresent([Character].self, forKey: .characters) ?? []
        activeCharacterID = try c.decodeIfPresent(UUID.self, forKey: .activeCharacterID)
        takes = try c.decodeIfPresent([TakeRecord].self, forKey: .takes) ?? []
        nextSequence = try c.decodeIfPresent(Int.self, forKey: .nextSequence) ?? (takes.map(\.sequence).max() ?? 0)
        transcripts = try c.decodeIfPresent([String: [TimedWord]].self, forKey: .transcripts) ?? [:]
        convertedAudio = try c.decodeIfPresent([String: String].self, forKey: .convertedAudio) ?? [:]
        conversionDrift = try c.decodeIfPresent([String: Double].self, forKey: .conversionDrift) ?? [:]
        effects = try c.decodeIfPresent([EffectRecord].self, forKey: .effects) ?? []
        music = try c.decodeIfPresent(MusicRecord.self, forKey: .music)
        mix = try c.decodeIfPresent(MixLevels.self, forKey: .mix) ?? MixLevels()
        trimStart = try c.decodeIfPresent(Double.self, forKey: .trimStart)
        trimEnd = try c.decodeIfPresent(Double.self, forKey: .trimEnd)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        voice = try c.decodeIfPresent(Voice.self, forKey: .voice)
        speechFile = try c.decodeIfPresent(String.self, forKey: .speechFile)
        typeCaptions = try c.decodeIfPresent([Caption].self, forKey: .typeCaptions) ?? []
        exportFile = try c.decodeIfPresent(String.self, forKey: .exportFile)
    }
}
