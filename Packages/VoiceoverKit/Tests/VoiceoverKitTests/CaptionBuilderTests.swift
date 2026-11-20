import Testing
@testable import VoiceoverKit

struct CaptionBuilderTests {
    @Test func charactersAreGroupedIntoTimedWords() {
        let alignment = makeAlignment("Hi  there.", step: 0.1)

        let words = CaptionBuilder.words(from: alignment)

        #expect(words == [
            TimedWord(text: "Hi", start: 0.0, end: 0.2),
            TimedWord(text: "there.", start: 0.4, end: 1.0),
        ])
    }

    @Test func captionsBreakAfterSentencePunctuation() {
        let words = makeWords("One two. Three four?")

        let captions = CaptionBuilder.captions(from: words)

        #expect(captions.map(\.text) == ["One two.", "Three four?"])
        #expect(captions.map(\.id) == [0, 1])
    }

    @Test func captionsRespectCharacterLimit() {
        let words = makeWords("alpha beta gamma delta epsilon")

        let captions = CaptionBuilder.captions(from: words, maxCharacters: 12)

        #expect(captions.map(\.text) == ["alpha beta", "gamma delta", "epsilon"])
        #expect(captions.allSatisfy { $0.text.count <= 12 })
    }

    @Test func captionsRespectDurationLimit() {
        let words = makeWords("a b c d e f", wordDuration: 1)

        let captions = CaptionBuilder.captions(from: words, maxDuration: 2)

        #expect(captions.map(\.text) == ["a b", "c d", "e f"])
        #expect(captions[1].start == 2 && captions[1].end == 4)
    }

    @Test func mismatchedArraysDoNotCrash() {
        let alignment = CharacterAlignment(characters: ["a", "b", "c"], startTimes: [0, 0.1], endTimes: [0.1])

        #expect(CaptionBuilder.words(from: alignment) == [TimedWord(text: "a", start: 0, end: 0.1)])
    }

    private func makeAlignment(_ text: String, step: Double) -> CharacterAlignment {
        let characters = text.map(String.init)
        let starts = characters.indices.map { Double($0) * step }

        return CharacterAlignment(characters: characters, startTimes: starts, endTimes: starts.map { $0 + step })
    }

    private func makeWords(_ text: String, wordDuration: Double = 0.3) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), start: Double(index) * wordDuration, end: Double(index + 1) * wordDuration)
        }
    }
}
