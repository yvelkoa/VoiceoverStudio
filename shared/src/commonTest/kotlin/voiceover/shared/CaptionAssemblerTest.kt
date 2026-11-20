package voiceover.shared

import voiceover.shared.captions.CaptionAssembler
import voiceover.shared.captions.TimedWord
import voiceover.shared.timeline.Take
import voiceover.shared.timeline.TakeResolver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.uuid.Uuid

/** Port of `CaptionAssemblerTests.swift`: same inputs, same expected outputs. */
class CaptionAssemblerTest {
    private val narrator = Uuid.random()
    private val dog = Uuid.random()
    private val file = "/tmp/take.m4a"

    @Test
    fun wordsAreShiftedOntoTheTimelineAndCutToTheSegment() {
        val take = Take(characterId = narrator, start = 10.0, duration = 4.0, recording = file, sequence = 1)
        val redo = Take(characterId = narrator, start = 12.0, duration = 2.0, recording = file, sequence = 2)
        val transcripts = mapOf(
            take.id to listOf(
                TimedWord("Good", start = 0.0, end = 0.4),
                TimedWord("boy.", start = 0.5, end = 0.9),
                TimedWord("Cut", start = 2.5, end = 2.9), // inside the redone part, must vanish
            ),
            redo.id to listOf(TimedWord("Sit!", start = 0.2, end = 0.6)),
        )

        val captions = CaptionAssembler.captions(
            segments = TakeResolver.segments(listOf(take, redo)),
            takes = listOf(take, redo),
            transcripts = transcripts,
            characterOrder = listOf(narrator),
        )

        assertEquals(listOf("Good boy.", "Sit!"), captions.map { it.text })
        assertEquals(listOf(10.0, 12.2), captions.map { it.start })
        assertTrue(captions.all { it.track == 0 })
    }

    @Test
    fun charactersGetTheirOwnTrackInDeclaredOrder() {
        val narration = Take(characterId = narrator, start = 0.0, duration = 3.0, recording = file, sequence = 1)
        val bark = Take(characterId = dog, start = 1.0, duration = 1.0, recording = file, sequence = 2)
        val transcripts = mapOf(
            narration.id to listOf(TimedWord("Hello.", start = 0.0, end = 1.0)),
            bark.id to listOf(TimedWord("Woof!", start = 0.0, end = 0.5)),
        )

        val captions = CaptionAssembler.captions(
            segments = TakeResolver.segments(listOf(narration, bark)),
            takes = listOf(narration, bark),
            transcripts = transcripts,
            characterOrder = listOf(dog, narrator),
        )

        assertEquals(listOf("Hello.", "Woof!"), captions.map { it.text })
        assertEquals(listOf(1, 0), captions.map { it.track })
        assertEquals(2, captions.map { it.id }.toSet().size, "ids stay unique across characters")
    }

    @Test
    fun takesWithoutTranscriptProduceNoCaptions() {
        val take = Take(characterId = narrator, start = 0.0, duration = 3.0, recording = file, sequence = 1)
        val captions = CaptionAssembler.captions(
            segments = TakeResolver.segments(listOf(take)),
            takes = listOf(take),
            transcripts = emptyMap(),
            characterOrder = listOf(narrator),
        )
        assertTrue(captions.isEmpty())
    }
}
