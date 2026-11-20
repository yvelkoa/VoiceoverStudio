package voiceover.shared.captions

import voiceover.shared.timeline.AudioSegment
import voiceover.shared.timeline.Take
import kotlin.uuid.Uuid

/** Builds captions for a multi-take, multi-character edit. */
public object CaptionAssembler {
    /**
     * @param segments the audible slices after overlap resolution.
     * @param takes every take, so a segment can be traced back to its character.
     * @param transcripts words per take, timed from the start of the take's recording.
     * @param characterOrder decides the caption track (line) of each character.
     */
    public fun captions(
        segments: List<AudioSegment>,
        takes: List<Take>,
        transcripts: Map<Uuid, List<TimedWord>>,
        characterOrder: List<Uuid>,
    ): List<Caption> {
        val takesById = takes.associateBy { it.id }
        val wordsByCharacter = mutableMapOf<Uuid, MutableList<TimedWord>>()

        for (segment in segments) {
            val take = takesById[segment.takeId] ?: continue
            val words = transcripts[take.id] ?: continue
            // Only words that start inside the slice survive; the shift moves them onto the timeline.
            val shift = segment.start - segment.sourceOffset
            val sliceEnd = segment.sourceOffset + segment.duration
            wordsByCharacter.getOrPut(take.characterId) { mutableListOf() } += words
                .filter { it.start >= segment.sourceOffset && it.start < sliceEnd }
                .map { TimedWord(it.text, it.start + shift, it.end + shift) }
        }

        val captions = mutableListOf<Caption>()
        characterOrder.forEachIndexed { track, characterId ->
            val words = wordsByCharacter[characterId]?.sortedBy { it.start } ?: return@forEachIndexed
            captions += CaptionBuilder.captions(words, track = track, firstId = captions.size)
        }
        return captions.sortedWith(compareBy({ it.start }, { it.track }))
    }
}
