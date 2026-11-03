import Foundation
import Testing
@testable import VoiceoverKit

struct CodableTests {
    @Test func voiceAndCharacterRoundTrip() throws {
        let voice = Voice(
            voiceID: "v1",
            name: "Rachel",
            category: "premade",
            labels: ["accent": "american"],
            previewURL: URL(string: "https://example.com/r.mp3")
        )
        let settings = VoiceSettings(stability: 0.3, speed: 1.1)
        let character = Character(name: "Narrator", voice: voice, settings: settings, colorIndex: 2)

        let data = try JSONEncoder().encode(character)
        let decoded = try JSONDecoder().decode(Character.self, from: data)

        #expect(decoded == character)
    }

    @Test func wordsAndCaptionsRoundTrip() throws {
        let words = [TimedWord(text: "Hi", start: 0.1, end: 0.4)]
        let captions = [Caption(id: 3, text: "Hi", start: 0.1, end: 0.4, track: 1)]

        #expect(try JSONDecoder().decode([TimedWord].self, from: JSONEncoder().encode(words)) == words)
        #expect(try JSONDecoder().decode([Caption].self, from: JSONEncoder().encode(captions)) == captions)
    }
}
