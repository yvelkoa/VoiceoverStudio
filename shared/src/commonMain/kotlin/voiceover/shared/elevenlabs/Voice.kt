package voiceover.shared.elevenlabs

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** A voice available to the account (`GET /v1/voices`). */
@Serializable
public data class Voice(
    @SerialName("voice_id") val voiceId: String,
    val name: String,
    val category: String? = null,
    @Serializable(with = LenientLabelsSerializer::class) val labels: Map<String, String> = emptyMap(),
    /** The Swift type holds a `URL`; here it stays the string the API sent. */
    @SerialName("preview_url") @Serializable(with = LenientStringSerializer::class) val previewUrl: String? = null,
) {
    val id: String get() = voiceId

    /** Short human-readable description built from labels, e.g. "american · young · female". */
    val summary: String
        get() = listOf("accent", "age", "gender", "use_case").mapNotNull { labels[it] }.joinToString(" · ")
}

@Serializable
internal data class VoicesResponse(val voices: List<Voice>)

/** Labels are free-form; a single non-string value must not fail the whole voice list, it empties the labels. */
internal object LenientLabelsSerializer : KSerializer<Map<String, String>> {
    private val delegate = MapSerializer(String.serializer(), String.serializer())
    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun serialize(encoder: Encoder, value: Map<String, String>): Unit = delegate.serialize(encoder, value)

    override fun deserialize(decoder: Decoder): Map<String, String> {
        val json = decoder as? JsonDecoder ?: return delegate.deserialize(decoder)
        val labels = json.decodeJsonElement() as? JsonObject ?: return emptyMap()
        if (labels.values.any { it !is JsonPrimitive || !it.isString }) return emptyMap()
        return labels.mapValues { (_, value) -> (value as JsonPrimitive).content }
    }
}

/** A string that decodes to null instead of failing when the value has another type or is empty. */
internal object LenientStringSerializer : KSerializer<String?> {
    private val delegate = String.serializer().nullable
    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun serialize(encoder: Encoder, value: String?): Unit = delegate.serialize(encoder, value)

    override fun deserialize(decoder: Decoder): String? {
        val json = decoder as? JsonDecoder ?: return delegate.deserialize(decoder)
        val value = json.decodeJsonElement() as? JsonPrimitive ?: return null
        return value.content.takeIf { value.isString && it.isNotEmpty() }
    }
}
