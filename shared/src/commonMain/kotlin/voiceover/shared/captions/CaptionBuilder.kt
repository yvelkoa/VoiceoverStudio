package voiceover.shared.captions

import voiceover.shared.elevenlabs.CharacterAlignment

/** Turns character-level alignment into short on-screen captions. */
public object CaptionBuilder {
    /** Groups characters into words. A word starts with its first character and ends with its last one. */
    public fun words(alignment: CharacterAlignment): List<TimedWord> {
        val count = minOf(alignment.characters.size, alignment.startTimes.size, alignment.endTimes.size)
        val words = mutableListOf<TimedWord>()
        val text = StringBuilder()
        var start = 0.0
        var end = 0.0

        fun flush() {
            if (text.isEmpty()) return
            words += TimedWord(text.toString(), start, end)
            text.clear()
        }

        for (i in 0 until count) {
            val character = alignment.characters[i]
            if (character.all { it.isUnicodeWhiteSpace() }) {
                flush()
                continue
            }
            if (text.isEmpty()) start = alignment.startTimes[i]
            text.append(character)
            end = alignment.endTimes[i]
        }
        flush()
        return words
    }

    /** Packs words into captions that stay short enough to read, breaking early after sentence punctuation. */
    public fun captions(
        words: List<TimedWord>,
        maxCharacters: Int = 32,
        maxDuration: Double = 3.0,
        track: Int = 0,
        firstId: Int = 0,
    ): List<Caption> {
        val captions = mutableListOf<Caption>()
        val line = mutableListOf<TimedWord>()

        fun flush() {
            if (line.isEmpty()) return
            captions += Caption(
                id = firstId + captions.size,
                text = line.joinToString(" ") { it.text },
                start = line.first().start,
                end = line.last().end,
                track = track,
            )
            line.clear()
        }

        for (word in words) {
            line.firstOrNull()?.let { first ->
                val length = line.sumOf { it.text.codePointCount() + 1 } + word.text.codePointCount()
                if (length > maxCharacters || word.end - first.start > maxDuration) flush()
            }
            line += word
            if (word.text.lastOrNull()?.let { it in ".!?" } == true) flush()
        }
        flush()
        return captions
    }

    public fun captions(alignment: CharacterAlignment): List<Caption> = captions(words(alignment))
}
