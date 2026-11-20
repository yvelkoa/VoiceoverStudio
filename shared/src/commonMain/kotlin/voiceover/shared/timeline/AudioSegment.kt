package voiceover.shared.timeline

import kotlin.uuid.Uuid

/** A slice of a take that survives overlap resolution and goes into the mix. */
public data class AudioSegment(
    val takeId: Uuid,
    val characterId: Uuid,
    /** Position on the timeline. */
    val start: Double,
    /** Offset into the take's recording where this slice begins. */
    val sourceOffset: Double,
    val duration: Double,
) {
    val end: Double get() = start + duration
}
