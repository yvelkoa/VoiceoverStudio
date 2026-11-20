package voiceover.shared.timeline

/**
 * Resolves overlapping takes into the segments that are actually heard.
 *
 * A character can't talk over themselves, so within one character the most recent take wins wherever
 * takes overlap. Different characters are independent: their takes may overlap freely, as in a dialogue.
 */
public object TakeResolver {
    /** Slices shorter than this are dropped; they are inaudible and only clutter the composition. */
    public const val MINIMUM_DURATION: Double = 0.05

    public fun segments(takes: List<Take>, minimumDuration: Double = MINIMUM_DURATION): List<AudioSegment> {
        val result = mutableListOf<AudioSegment>()

        for (group in takes.groupBy { it.characterId }.values) {
            val ordered = group.sortedBy { it.sequence }
            ordered.forEachIndexed { index, take ->
                var remaining = listOf(take.start..take.end)
                for (other in ordered.drop(index + 1)) {
                    remaining = remaining.flatMap { subtract(other.start..other.end, from = it) }
                }
                for (range in remaining) {
                    val duration = range.endInclusive - range.start
                    if (duration < minimumDuration) continue
                    result += AudioSegment(
                        takeId = take.id,
                        characterId = take.characterId,
                        start = range.start,
                        sourceOffset = range.start - take.start,
                        duration = duration,
                    )
                }
            }
        }

        // Swift orders by `uuidString` (upper-case hex); lower-case hex sorts the same way.
        return result.sortedWith(compareBy({ it.start }, { it.characterId.toString() }))
    }

    /** Removes [cut] from [from]; the result is zero, one or two pieces. */
    private fun subtract(
        cut: ClosedFloatingPointRange<Double>,
        from: ClosedFloatingPointRange<Double>,
    ): List<ClosedFloatingPointRange<Double>> {
        if (!(cut.start < from.endInclusive && cut.endInclusive > from.start)) return listOf(from)
        return buildList {
            if (cut.start > from.start) add(from.start..cut.start)
            if (cut.endInclusive < from.endInclusive) add(cut.endInclusive..from.endInclusive)
        }
    }
}
