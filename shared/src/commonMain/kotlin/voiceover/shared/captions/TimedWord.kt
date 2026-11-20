package voiceover.shared.captions

import kotlinx.serialization.Serializable

@Serializable
public data class TimedWord(
    val text: String,
    val start: Double,
    val end: Double,
)
