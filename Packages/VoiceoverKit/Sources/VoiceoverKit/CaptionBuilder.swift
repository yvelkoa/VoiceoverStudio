import Foundation

public struct TimedWord: Equatable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct Caption: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let start: Double
    public let end: Double

    public init(id: Int, text: String, start: Double, end: Double) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Turns character-level alignment into short on-screen captions.
public enum CaptionBuilder {
    /// Groups characters into words. A word starts with its first character and ends with its last one.
    public static func words(from alignment: CharacterAlignment) -> [TimedWord] {
        let count = min(alignment.characters.count, alignment.startTimes.count, alignment.endTimes.count)
        var words: [TimedWord] = []
        var text = ""
        var start = 0.0
        var end = 0.0

        func flush() {
            guard !text.isEmpty else { return }
            words.append(TimedWord(text: text, start: start, end: end))
            text = ""
        }

        for i in 0..<count {
            let character = alignment.characters[i]
            if character.allSatisfy(\.isWhitespace) {
                flush()
                continue
            }
            if text.isEmpty { start = alignment.startTimes[i] }
            text += character
            end = alignment.endTimes[i]
        }
        flush()
        return words
    }

    /// Packs words into captions that stay short enough to read, breaking early after sentence punctuation.
    public static func captions(
        from words: [TimedWord],
        maxCharacters: Int = 32,
        maxDuration: Double = 3
    ) -> [Caption] {
        var captions: [Caption] = []
        var line: [TimedWord] = []

        func flush() {
            guard let first = line.first, let last = line.last else { return }
            let text = line.map(\.text).joined(separator: " ")
            captions.append(Caption(id: captions.count, text: text, start: first.start, end: last.end))
            line.removeAll()
        }

        for word in words {
            if let first = line.first {
                let length = line.reduce(0) { $0 + $1.text.count + 1 } + word.text.count
                if length > maxCharacters || word.end - first.start > maxDuration {
                    flush()
                }
            }
            line.append(word)
            if let last = word.text.last, ".!?".contains(last) {
                flush()
            }
        }
        flush()
        return captions
    }

    public static func captions(from alignment: CharacterAlignment) -> [Caption] {
        captions(from: words(from: alignment))
    }
}
