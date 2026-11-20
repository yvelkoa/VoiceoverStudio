package voiceover.shared.captions

import kotlinx.serialization.Serializable

@Serializable
public data class Caption(
    val id: Int,
    val text: String,
    val start: Double,
    val end: Double,
    /** Which line the caption is drawn on when several are visible at once (one per speaker). */
    val track: Int = 0,
)
