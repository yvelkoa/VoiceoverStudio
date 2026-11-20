package voiceover.shared.elevenlabs

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Per-character timing returned by `text-to-speech/{voice_id}/with-timestamps`. */
@Serializable
public data class CharacterAlignment(
    val characters: List<String>,
    @SerialName("character_start_times_seconds") val startTimes: List<Double>,
    @SerialName("character_end_times_seconds") val endTimes: List<Double>,
)

/** Generated speech: encoded audio (MP3) plus the timing of every character in the script. */
public class Speech(
    public val audio: ByteArray,
    public val alignment: CharacterAlignment,
)

@Serializable
internal data class SpeechResponse(
    @SerialName("audio_base64") val audioBase64: String,
    val alignment: CharacterAlignment? = null,
    @SerialName("normalized_alignment") val normalizedAlignment: CharacterAlignment? = null,
)

@Serializable
internal data class SpeechRequest(
    val text: String,
    @SerialName("model_id") val modelId: String,
    @SerialName("voice_settings") val voiceSettings: VoiceSettings? = null,
)
