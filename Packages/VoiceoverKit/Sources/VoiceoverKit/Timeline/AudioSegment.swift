import Foundation

/// A slice of a take that survives overlap resolution and goes into the mix.
public struct AudioSegment: Hashable, Sendable {
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
