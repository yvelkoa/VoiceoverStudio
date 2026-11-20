import Foundation

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
