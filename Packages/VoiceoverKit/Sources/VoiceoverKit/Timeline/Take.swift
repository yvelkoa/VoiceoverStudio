import Foundation

/// One recorded pass of the microphone, placed on the timeline for one character.
public struct Take: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var characterID: UUID
    /// Where the recording starts on the video's timeline, in seconds.
    public var start: Double
    public var duration: Double
    public var recording: URL
    /// Recording order. A later take replaces earlier ones where they overlap.
    public var sequence: Int

    public init(id: UUID = UUID(), characterID: UUID, start: Double, duration: Double, recording: URL, sequence: Int) {
        self.id = id
        self.characterID = characterID
        self.start = start
        self.duration = duration
        self.recording = recording
        self.sequence = sequence
    }

    public var end: Double { start + duration }
}
