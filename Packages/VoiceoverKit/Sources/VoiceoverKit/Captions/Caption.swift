import Foundation

public struct Caption: Identifiable, Equatable, Codable, Sendable {
    public let id: Int
    public let text: String
    public let start: Double
    public let end: Double
    /// Which line the caption is drawn on when several are visible at once (one per speaker).
    public let track: Int

    public init(id: Int, text: String, start: Double, end: Double, track: Int = 0) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.track = track
    }
}
