import Foundation
import Testing
@testable import VoiceoverKit

struct CaptionAssemblerTests {
    private let narrator = UUID()
    private let dog = UUID()
    private let file = URL(fileURLWithPath: "/tmp/take.m4a")

    @Test func wordsAreShiftedOntoTheTimelineAndCutToTheSegment() {
        let take = Take(characterID: narrator, start: 10, duration: 4, recording: file, sequence: 1)
        let redo = Take(characterID: narrator, start: 12, duration: 2, recording: file, sequence: 2)
        let transcripts: [Take.ID: [TimedWord]] = [
            take.id: [
                TimedWord(text: "Good", start: 0.0, end: 0.4),
                TimedWord(text: "boy.", start: 0.5, end: 0.9),
                TimedWord(text: "Cut", start: 2.5, end: 2.9), // inside the redone part, must vanish
            ],
            redo.id: [TimedWord(text: "Sit!", start: 0.2, end: 0.6)],
        ]

        let captions = CaptionAssembler.captions(
            segments: TakeResolver.segments(for: [take, redo]),
            takes: [take, redo],
            transcripts: transcripts,
            characterOrder: [narrator]
        )

        #expect(captions.map(\.text) == ["Good boy.", "Sit!"])
        #expect(captions.map(\.start) == [10.0, 12.2])
        #expect(captions.allSatisfy { $0.track == 0 })
    }

    @Test func charactersGetTheirOwnTrackInDeclaredOrder() {
        let narration = Take(characterID: narrator, start: 0, duration: 3, recording: file, sequence: 1)
        let bark = Take(characterID: dog, start: 1, duration: 1, recording: file, sequence: 2)
        let transcripts: [Take.ID: [TimedWord]] = [
            narration.id: [TimedWord(text: "Hello.", start: 0, end: 1)],
            bark.id: [TimedWord(text: "Woof!", start: 0, end: 0.5)],
        ]

        let captions = CaptionAssembler.captions(
            segments: TakeResolver.segments(for: [narration, bark]),
            takes: [narration, bark],
            transcripts: transcripts,
            characterOrder: [dog, narrator]
        )

        #expect(captions.map(\.text) == ["Hello.", "Woof!"])
        #expect(captions.map(\.track) == [1, 0])
        #expect(Set(captions.map(\.id)).count == 2, "ids stay unique across characters")
    }

    @Test func takesWithoutTranscriptProduceNoCaptions() {
        let take = Take(characterID: narrator, start: 0, duration: 3, recording: file, sequence: 1)
        let captions = CaptionAssembler.captions(
            segments: TakeResolver.segments(for: [take]),
            takes: [take],
            transcripts: [:],
            characterOrder: [narrator]
        )
        #expect(captions.isEmpty)
    }
}
