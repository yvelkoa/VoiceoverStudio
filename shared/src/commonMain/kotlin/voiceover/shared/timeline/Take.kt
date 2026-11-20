package voiceover.shared.timeline

import kotlin.uuid.Uuid

/** One recorded pass of the microphone, placed on the timeline for one character. */
public data class Take(
    val id: Uuid = Uuid.random(),
    val characterId: Uuid,
    /** Where the recording starts on the video's timeline, in seconds. */
    val start: Double,
    val duration: Double,
    /** Path of the recording. The Swift type holds a file `URL`; common Kotlin has no equivalent. */
    val recording: String,
    /** Recording order. A later take replaces earlier ones where they overlap. */
    val sequence: Int,
) {
    val end: Double get() = start + duration
}
