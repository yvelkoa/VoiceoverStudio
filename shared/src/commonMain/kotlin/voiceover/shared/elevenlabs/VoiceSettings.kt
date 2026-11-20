package voiceover.shared.elevenlabs

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Per-request overrides for how a voice performs. Null fields keep the voice's stored defaults. */
@Serializable
public data class VoiceSettings(
    /** 0...1. Lower gives a wider emotional range, higher sounds steadier but flatter. */
    val stability: Double? = null,
    /** 0...1. How closely the output sticks to the original voice. */
    @SerialName("similarity_boost") val similarityBoost: Double? = null,
    /** 0...1. Exaggerates the speaker's style; non-zero costs latency. */
    val style: Double? = null,
    /** 0.7...1.2. 1.0 is the voice's natural pace. */
    val speed: Double? = null,
    @SerialName("use_speaker_boost") val useSpeakerBoost: Boolean? = null,
) {
    public companion object {
        /** Steady, narrator-like delivery. */
        public val narration: VoiceSettings = VoiceSettings(stability = 0.75, similarityBoost = 0.75, style = 0.0)

        /** Follows the source performance closely; the default for voice conversion. */
        public val expressive: VoiceSettings = VoiceSettings(stability = 0.3, similarityBoost = 0.8, style = 0.4)
    }
}
