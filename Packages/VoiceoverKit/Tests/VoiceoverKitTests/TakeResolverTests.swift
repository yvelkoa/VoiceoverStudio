import Foundation
import Testing
@testable import VoiceoverKit

struct TakeResolverTests {
    private let narrator = UUID()
    private let dog = UUID()
    private let file = URL(fileURLWithPath: "/tmp/take.m4a")

    private func take(_ character: UUID, _ start: Double, _ duration: Double, seq: Int) -> Take {
        Take(characterID: character, start: start, duration: duration, recording: file, sequence: seq)
    }

    @Test func nonOverlappingTakesAreKeptWholeAndSortedByStart() {
        let later = take(narrator, 10, 3, seq: 1)
        let earlier = take(narrator, 0, 4, seq: 2)

        let segments = TakeResolver.segments(for: [later, earlier])

        #expect(segments.map(\.takeID) == [earlier.id, later.id])
        #expect(segments.map(\.sourceOffset) == [0, 0])
        #expect(segments.map(\.duration) == [4, 3])
    }

    @Test func newerTakeReplacesOlderWhereTheyOverlap() {
        let first = take(narrator, 0, 10, seq: 1)
        let redo = take(narrator, 6, 6, seq: 2)

        let segments = TakeResolver.segments(for: [first, redo])

        #expect(segments.count == 2)
        #expect(segments[0] == AudioSegment(takeID: first.id, characterID: narrator, start: 0, sourceOffset: 0, duration: 6))
        #expect(segments[1] == AudioSegment(takeID: redo.id, characterID: narrator, start: 6, sourceOffset: 0, duration: 6))
    }

    @Test func newerTakeInTheMiddleSplitsTheOlderOne() {
        let first = take(narrator, 0, 10, seq: 1)
        let punchIn = take(narrator, 3, 2, seq: 2)

        let segments = TakeResolver.segments(for: [first, punchIn])

        #expect(segments.map(\.takeID) == [first.id, punchIn.id, first.id])
        #expect(segments.map(\.start) == [0, 3, 5])
        #expect(segments.map(\.sourceOffset) == [0, 0, 5], "the tail keeps its offset into the original file")
        #expect(segments.map(\.duration) == [3, 2, 5])
    }

    @Test func olderTakeFullyCoveredDisappears() {
        let first = take(narrator, 2, 3, seq: 1)
        let redo = take(narrator, 0, 10, seq: 2)

        let segments = TakeResolver.segments(for: [first, redo])

        #expect(segments.map(\.takeID) == [redo.id])
    }

    @Test func charactersDoNotCutEachOther() {
        let narration = take(narrator, 0, 10, seq: 1)
        let bark = take(dog, 4, 2, seq: 2)

        let segments = TakeResolver.segments(for: [narration, bark])

        #expect(segments.count == 2)
        #expect(segments.map(\.duration) == [10, 2])
    }

    @Test func slicesBelowMinimumDurationAreDropped() {
        let first = take(narrator, 0, 5, seq: 1)
        let redo = take(narrator, 0.02, 5, seq: 2)

        let segments = TakeResolver.segments(for: [first, redo])

        #expect(segments.map(\.takeID) == [redo.id], "a 20 ms sliver of the first take is not worth a track")
    }

    @Test func emptyInputGivesEmptyOutput() {
        #expect(TakeResolver.segments(for: []).isEmpty)
    }
}
