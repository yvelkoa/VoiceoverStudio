import Foundation

/// Builds captions for a multi-take, multi-character edit.
public enum CaptionAssembler {
    /// - Parameters:
    ///   - segments: the audible slices after overlap resolution.
    ///   - takes: every take, so a segment can be traced back to its character.
    ///   - transcripts: words per take, timed from the start of the take's recording.
    ///   - characterOrder: decides the caption track (line) of each character.
    public static func captions(
        segments: [AudioSegment],
        takes: [Take],
        transcripts: [Take.ID: [TimedWord]],
        characterOrder: [UUID]
    ) -> [Caption] {
        let takesByID = Dictionary(uniqueKeysWithValues: takes.map { ($0.id, $0) })
        var wordsByCharacter: [UUID: [TimedWord]] = [:]

        for segment in segments {
            guard let take = takesByID[segment.takeID], let words = transcripts[take.id] else { continue }
            // Only words that start inside the slice survive; the shift moves them onto the timeline.
            let shift = segment.start - segment.sourceOffset
            let inside = words.filter { $0.start >= segment.sourceOffset && $0.start < segment.sourceOffset + segment.duration }
            wordsByCharacter[take.characterID, default: []] += inside.map {
                TimedWord(text: $0.text, start: $0.start + shift, end: $0.end + shift)
            }
        }

        var captions: [Caption] = []
        for (track, characterID) in characterOrder.enumerated() {
            guard let words = wordsByCharacter[characterID]?.sorted(by: { $0.start < $1.start }) else { continue }
            captions += CaptionBuilder.captions(from: words, track: track, firstID: captions.count)
        }
        return captions.sorted { ($0.start, $0.track) < ($1.start, $1.track) }
    }
}
