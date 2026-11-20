import Foundation
import Shared
import Testing
import VoiceoverKit

/// The Kotlin port and the Swift reference get the same input; their outputs must be equal.
struct CaptionComparisonTests {
    private static let scripts = [
        "Hi  there.",
        "One two. Three four? Five!",
        "Привет, это озвучка поверх видео. Дуже довгий рядок українською мовою без жодної крапки всередині",
        "tabs\tand\nnewlines\u{00A0}and\u{2003}wide\u{0085}spaces",
        "   leading and trailing   ",
        "",
    ]

    @Test(arguments: scripts)
    func wordsMatch(script: String) {
        let alignment = Self.alignment(for: script, step: 0.07)

        let swift = VoiceoverKit.CaptionBuilder.words(from: alignment)
        let kotlin = Shared.CaptionBuilder.shared.words(alignment: alignment.kotlin).map(\.swift)

        #expect(kotlin == swift)
    }

    @Test(arguments: scripts)
    func captionsFromAlignmentMatch(script: String) {
        let alignment = Self.alignment(for: script, step: 0.07)

        let swift = VoiceoverKit.CaptionBuilder.captions(from: alignment).map(CaptionSnapshot.init)
        let kotlin = Shared.CaptionBuilder.shared.captions(alignment: alignment.kotlin).map(CaptionSnapshot.init)

        #expect(kotlin == swift)
    }

    @Test func mismatchedArraysMatch() {
        let alignment = VoiceoverKit.CharacterAlignment(characters: ["a", "b", "c"], startTimes: [0, 0.1], endTimes: [0.1])

        let swift = VoiceoverKit.CaptionBuilder.words(from: alignment)
        let kotlin = Shared.CaptionBuilder.shared.words(alignment: alignment.kotlin).map(\.swift)

        #expect(kotlin == swift)
        #expect(kotlin.count == 1)
    }

    /// 500 generated transcripts with random limits: word lengths, pauses and punctuation vary.
    @Test func captionsMatchOnGeneratedTranscripts() {
        var generator = SeededGenerator(seed: 2026)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzабвгдежзийклмнопрстуфхцчшщьюяіїєґ")
        var compared = 0

        for _ in 0..<500 {
            var words: [VoiceoverKit.TimedWord] = []
            var clock = 0.0
            for _ in 0..<Int.random(in: 0...40, using: &generator) {
                var text = String((0..<Int.random(in: 1...14, using: &generator)).map { _ in
                    alphabet.randomElement(using: &generator) ?? "a"
                })
                if Int.random(in: 0..<6, using: &generator) == 0 {
                    text.append([".", "!", "?", ","].randomElement(using: &generator) ?? ".")
                }
                clock += Double.random(in: 0...0.8, using: &generator)
                let end = clock + Double.random(in: 0.05...1.2, using: &generator)
                words.append(VoiceoverKit.TimedWord(text: text, start: clock, end: end))
                clock = end
            }
            let maxCharacters = Int.random(in: 8...48, using: &generator)
            let maxDuration = Double.random(in: 0.5...5, using: &generator)
            let track = Int.random(in: 0...3, using: &generator)
            let firstID = Int.random(in: 0...100, using: &generator)

            let swift = VoiceoverKit.CaptionBuilder.captions(
                from: words, maxCharacters: maxCharacters, maxDuration: maxDuration, track: track, firstID: firstID
            ).map(CaptionSnapshot.init)
            // Kotlin default arguments do not survive the Objective-C header: all five are spelled out.
            let kotlin = Shared.CaptionBuilder.shared.captions(
                words: words.map(\.kotlin),
                maxCharacters: Int32(maxCharacters),
                maxDuration: maxDuration,
                track: Int32(track),
                firstId: Int32(firstID)
            ).map(CaptionSnapshot.init)

            #expect(kotlin == swift)
            compared += swift.count
        }
        #expect(compared > 1000, "the corpus must actually exercise the packer")
    }

    /// Overlapping takes of two characters go through both resolvers and both assemblers.
    @Test func resolvedSegmentsAndAssembledCaptionsMatch() {
        var generator = SeededGenerator(seed: 7)
        let characters = [UUID(), UUID()]
        let file = URL(fileURLWithPath: "/tmp/take.m4a")

        for _ in 0..<200 {
            let takes = (0..<Int.random(in: 0...8, using: &generator)).map { sequence in
                VoiceoverKit.Take(
                    characterID: characters.randomElement(using: &generator) ?? characters[0],
                    start: Double(Int.random(in: 0...200, using: &generator)) / 10,
                    duration: Double(Int.random(in: 1...80, using: &generator)) / 10,
                    recording: file,
                    sequence: sequence
                )
            }
            var transcripts: [UUID: [VoiceoverKit.TimedWord]] = [:]
            for take in takes where Int.random(in: 0..<5, using: &generator) > 0 {
                transcripts[take.id] = stride(from: 0.0, to: take.duration, by: 0.45).enumerated().map { index, start in
                    VoiceoverKit.TimedWord(text: index % 4 == 3 ? "word." : "word\(index)", start: start, end: start + 0.4)
                }
            }

            let swiftSegments = VoiceoverKit.TakeResolver.segments(for: takes)
            let kotlinTakes = takes.map(\.kotlin)
            let kotlinSegments = Shared.TakeResolver.shared.segments(
                takes: kotlinTakes,
                minimumDuration: Shared.TakeResolver.shared.MINIMUM_DURATION
            )
            #expect(kotlinSegments.map(SegmentSnapshot.init) == swiftSegments.map(SegmentSnapshot.init))

            let swiftCaptions = VoiceoverKit.CaptionAssembler.captions(
                segments: swiftSegments, takes: takes, transcripts: transcripts, characterOrder: characters
            )
            let kotlinTranscripts = Dictionary(uniqueKeysWithValues: transcripts.map { ($0.key.kotlin, $0.value.map(\.kotlin)) })
            let kotlinCaptions = Shared.CaptionAssembler.shared.captions(
                segments: kotlinSegments,
                takes: kotlinTakes,
                transcripts: kotlinTranscripts,
                characterOrder: characters.map(\.kotlin)
            )
            #expect(kotlinCaptions.map(CaptionSnapshot.init) == swiftCaptions.map(CaptionSnapshot.init))
        }
    }

    /// The one place the port is knowingly not identical: Swift measures a caption in grapheme clusters,
    /// Kotlin's common stdlib can only count code points, so an emoji sequence weighs more on the Kotlin side.
    @Test func graphemeClustersAreCountedDifferently() {
        let family = "👨‍👩‍👧‍👦" // one Character in Swift, seven code points
        let words = (0..<4).map { VoiceoverKit.TimedWord(text: family, start: Double($0), end: Double($0) + 0.5) }

        let swift = VoiceoverKit.CaptionBuilder.captions(from: words, maxCharacters: 8, maxDuration: 60)
        let kotlin = Shared.CaptionBuilder.shared.captions(
            words: words.map(\.kotlin), maxCharacters: 8, maxDuration: 60, track: 0, firstId: 0
        )

        #expect(swift.count == 1)
        withKnownIssue("Kotlin counts code points, Swift counts grapheme clusters") {
            #expect(kotlin.map(CaptionSnapshot.init) == swift.map(CaptionSnapshot.init))
        }
    }

    private static func alignment(for text: String, step: Double) -> VoiceoverKit.CharacterAlignment {
        let characters = text.map(String.init)
        let starts = characters.indices.map { Double($0) * step }
        return VoiceoverKit.CharacterAlignment(characters: characters, startTimes: starts, endTimes: starts.map { $0 + step })
    }
}
