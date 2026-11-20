package voiceover.shared

import voiceover.shared.captions.CaptionBuilder
import voiceover.shared.captions.TimedWord
import voiceover.shared.elevenlabs.CharacterAlignment
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Port of `CaptionBuilderTests.swift`: same inputs, same expected outputs. */
class CaptionBuilderTest {
    @Test
    fun charactersAreGroupedIntoTimedWords() {
        val alignment = makeAlignment("Hi  there.", step = 0.1)

        val words = CaptionBuilder.words(alignment)

        assertEquals(
            listOf(
                TimedWord("Hi", start = 0.0, end = 0.2),
                TimedWord("there.", start = 0.4, end = 1.0),
            ),
            words,
        )
    }

    @Test
    fun captionsBreakAfterSentencePunctuation() {
        val words = makeWords("One two. Three four?")

        val captions = CaptionBuilder.captions(words)

        assertEquals(listOf("One two.", "Three four?"), captions.map { it.text })
        assertEquals(listOf(0, 1), captions.map { it.id })
    }

    @Test
    fun captionsRespectCharacterLimit() {
        val words = makeWords("alpha beta gamma delta epsilon")

        val captions = CaptionBuilder.captions(words, maxCharacters = 12)

        assertEquals(listOf("alpha beta", "gamma delta", "epsilon"), captions.map { it.text })
        assertTrue(captions.all { it.text.length <= 12 })
    }

    @Test
    fun captionsRespectDurationLimit() {
        val words = makeWords("a b c d e f", wordDuration = 1.0)

        val captions = CaptionBuilder.captions(words, maxDuration = 2.0)

        assertEquals(listOf("a b", "c d", "e f"), captions.map { it.text })
        assertTrue(captions[1].start == 2.0 && captions[1].end == 4.0)
    }

    @Test
    fun mismatchedArraysDoNotCrash() {
        val alignment = CharacterAlignment(listOf("a", "b", "c"), startTimes = listOf(0.0, 0.1), endTimes = listOf(0.1))

        assertEquals(listOf(TimedWord("a", start = 0.0, end = 0.1)), CaptionBuilder.words(alignment))
    }

    private fun makeAlignment(text: String, step: Double): CharacterAlignment {
        val characters = text.map { it.toString() }
        val starts = characters.indices.map { it * step }
        return CharacterAlignment(characters, startTimes = starts, endTimes = starts.map { it + step })
    }

    private fun makeWords(text: String, wordDuration: Double = 0.3): List<TimedWord> =
        text.split(" ").mapIndexed { index, word ->
            TimedWord(word, start = index * wordDuration, end = (index + 1) * wordDuration)
        }
}
