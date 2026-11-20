package voiceover.shared

import voiceover.shared.timeline.AudioSegment
import voiceover.shared.timeline.Take
import voiceover.shared.timeline.TakeResolver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.uuid.Uuid

/** Port of `TakeResolverTests.swift`: same inputs, same expected outputs. */
class TakeResolverTest {
    private val narrator = Uuid.random()
    private val dog = Uuid.random()

    private fun take(character: Uuid, start: Double, duration: Double, seq: Int) =
        Take(characterId = character, start = start, duration = duration, recording = "/tmp/take.m4a", sequence = seq)

    @Test
    fun nonOverlappingTakesAreKeptWholeAndSortedByStart() {
        val later = take(narrator, 10.0, 3.0, seq = 1)
        val earlier = take(narrator, 0.0, 4.0, seq = 2)

        val segments = TakeResolver.segments(listOf(later, earlier))

        assertEquals(listOf(earlier.id, later.id), segments.map { it.takeId })
        assertEquals(listOf(0.0, 0.0), segments.map { it.sourceOffset })
        assertEquals(listOf(4.0, 3.0), segments.map { it.duration })
    }

    @Test
    fun newerTakeReplacesOlderWhereTheyOverlap() {
        val first = take(narrator, 0.0, 10.0, seq = 1)
        val redo = take(narrator, 6.0, 6.0, seq = 2)

        val segments = TakeResolver.segments(listOf(first, redo))

        assertEquals(2, segments.size)
        assertEquals(AudioSegment(first.id, narrator, start = 0.0, sourceOffset = 0.0, duration = 6.0), segments[0])
        assertEquals(AudioSegment(redo.id, narrator, start = 6.0, sourceOffset = 0.0, duration = 6.0), segments[1])
    }

    @Test
    fun newerTakeInTheMiddleSplitsTheOlderOne() {
        val first = take(narrator, 0.0, 10.0, seq = 1)
        val punchIn = take(narrator, 3.0, 2.0, seq = 2)

        val segments = TakeResolver.segments(listOf(first, punchIn))

        assertEquals(listOf(first.id, punchIn.id, first.id), segments.map { it.takeId })
        assertEquals(listOf(0.0, 3.0, 5.0), segments.map { it.start })
        assertEquals(
            listOf(0.0, 0.0, 5.0),
            segments.map { it.sourceOffset },
            "the tail keeps its offset into the original file",
        )
        assertEquals(listOf(3.0, 2.0, 5.0), segments.map { it.duration })
    }

    @Test
    fun olderTakeFullyCoveredDisappears() {
        val first = take(narrator, 2.0, 3.0, seq = 1)
        val redo = take(narrator, 0.0, 10.0, seq = 2)

        val segments = TakeResolver.segments(listOf(first, redo))

        assertEquals(listOf(redo.id), segments.map { it.takeId })
    }

    @Test
    fun charactersDoNotCutEachOther() {
        val narration = take(narrator, 0.0, 10.0, seq = 1)
        val bark = take(dog, 4.0, 2.0, seq = 2)

        val segments = TakeResolver.segments(listOf(narration, bark))

        assertEquals(2, segments.size)
        assertEquals(listOf(10.0, 2.0), segments.map { it.duration })
    }

    @Test
    fun slicesBelowMinimumDurationAreDropped() {
        val first = take(narrator, 0.0, 5.0, seq = 1)
        val redo = take(narrator, 0.02, 5.0, seq = 2)

        val segments = TakeResolver.segments(listOf(first, redo))

        assertEquals(listOf(redo.id), segments.map { it.takeId }, "a 20 ms sliver of the first take is not worth a track")
    }

    @Test
    fun emptyInputGivesEmptyOutput() {
        assertTrue(TakeResolver.segments(emptyList()).isEmpty())
    }
}
