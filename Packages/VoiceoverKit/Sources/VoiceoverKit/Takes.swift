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

/// A slice of a take that survives overlap resolution and goes into the mix.
public struct AudioSegment: Equatable, Sendable {
    public let takeID: Take.ID
    public let characterID: UUID
    /// Position on the timeline.
    public let start: Double
    /// Offset into the take's recording where this slice begins.
    public let sourceOffset: Double
    public let duration: Double

    public init(takeID: Take.ID, characterID: UUID, start: Double, sourceOffset: Double, duration: Double) {
        self.takeID = takeID
        self.characterID = characterID
        self.start = start
        self.sourceOffset = sourceOffset
        self.duration = duration
    }

    public var end: Double { start + duration }
}

/// Resolves overlapping takes into the segments that are actually heard.
///
/// A character can't talk over themselves, so within one character the most recent take wins wherever
/// takes overlap. Different characters are independent: their takes may overlap freely, as in a dialogue.
public enum TakeResolver {
    /// Slices shorter than this are dropped; they are inaudible and only clutter the composition.
    public static let minimumDuration = 0.05

    public static func segments(for takes: [Take], minimumDuration: Double = minimumDuration) -> [AudioSegment] {
        let byCharacter = Dictionary(grouping: takes, by: \.characterID)
        var result: [AudioSegment] = []

        for (_, group) in byCharacter {
            let ordered = group.sorted { $0.sequence < $1.sequence }
            for (index, take) in ordered.enumerated() {
                let newer = ordered[(index + 1)...]
                var remaining: [ClosedRange<Double>] = [take.start...take.end]
                for other in newer {
                    remaining = remaining.flatMap { subtract(other.start...other.end, from: $0) }
                }
                for range in remaining where range.upperBound - range.lowerBound >= minimumDuration {
                    result.append(AudioSegment(
                        takeID: take.id,
                        characterID: take.characterID,
                        start: range.lowerBound,
                        sourceOffset: range.lowerBound - take.start,
                        duration: range.upperBound - range.lowerBound
                    ))
                }
            }
        }

        return result.sorted { ($0.start, $0.characterID.uuidString) < ($1.start, $1.characterID.uuidString) }
    }

    /// Removes `cut` from `range`; the result is zero, one or two pieces.
    private static func subtract(_ cut: ClosedRange<Double>, from range: ClosedRange<Double>) -> [ClosedRange<Double>] {
        guard cut.lowerBound < range.upperBound, cut.upperBound > range.lowerBound else { return [range] }
        var pieces: [ClosedRange<Double>] = []
        if cut.lowerBound > range.lowerBound { pieces.append(range.lowerBound...cut.lowerBound) }
        if cut.upperBound < range.upperBound { pieces.append(cut.upperBound...range.upperBound) }
        return pieces
    }
}
