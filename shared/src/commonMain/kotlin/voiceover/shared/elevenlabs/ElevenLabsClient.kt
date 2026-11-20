package voiceover.shared.elevenlabs

import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.URLBuilder
import io.ktor.http.appendPathSegments
import io.ktor.http.content.TextContent
import io.ktor.http.isSuccess
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.io.IOException
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlin.io.encoding.Base64

/**
 * Thin client over the ElevenLabs endpoints the caption pipeline needs: the voice list and text to speech
 * with timestamps. The Swift original is an actor because it owns the voice cache; here a [Mutex] guards it.
 *
 * @param httpClient any Ktor client; no plugins are required. Tests pass one backed by `MockEngine`.
 */
public class ElevenLabsClient(
    private val httpClient: HttpClient,
    private val baseUrl: String = DEFAULT_BASE_URL,
    private val apiKey: () -> String?,
) {
    /** Uses the platform engine (Darwin on iOS, CIO on the JVM) with the same 120 s timeout as the Swift client. */
    public constructor(apiKey: () -> String?) : this(defaultHttpClient(), DEFAULT_BASE_URL, apiKey)

    private val cacheLock = Mutex()
    private var cachedVoices: List<Voice>? = null

    /** Forgets the cached voice list, e.g. when the key is removed; the next [voices] fetches again. */
    public suspend fun clearCache() {
        cacheLock.withLock { cachedVoices = null }
    }

    @Throws(ElevenLabsError::class, CancellationException::class)
    public suspend fun voices(forceRefresh: Boolean = false): List<Voice> {
        if (!forceRefresh) cacheLock.withLock { cachedVoices }?.let { return it }
        val body = perform(HttpMethod.Get, "v1", "voices")
        val voices = decode(VoicesResponse.serializer(), body).voices
            .sortedWith { a, b -> compareLocalizedCaseInsensitive(a.name, b.name) }
        cacheLock.withLock { cachedVoices = voices }
        return voices
    }

    /** Text to speech with per-character timestamps, used to sync captions to the voice. */
    @Throws(ElevenLabsError::class, CancellationException::class)
    public suspend fun speech(
        text: String,
        voiceId: String,
        modelId: String = DEFAULT_MODEL_ID,
        settings: VoiceSettings? = null,
    ): Speech {
        val request = json.encodeToString(SpeechRequest.serializer(), SpeechRequest(text, modelId, settings))
        val body = perform(
            HttpMethod.Post, "v1", "text-to-speech", voiceId, "with-timestamps",
            query = mapOf("output_format" to OUTPUT_FORMAT),
            jsonBody = request,
        )
        val response = decode(SpeechResponse.serializer(), body)
        val audio = try {
            Base64.decode(response.audioBase64)
        } catch (_: IllegalArgumentException) {
            throw ElevenLabsError.Decoding()
        }
        // `alignment` matches the original script; the normalized one spells out numbers etc.
        val alignment = response.alignment ?: response.normalizedAlignment ?: throw ElevenLabsError.Decoding()
        return Speech(audio, alignment)
    }

    private suspend fun perform(
        method: HttpMethod,
        vararg path: String,
        query: Map<String, String> = emptyMap(),
        jsonBody: String? = null,
    ): String {
        val key = apiKey()
        if (key.isNullOrEmpty()) throw ElevenLabsError.MissingApiKey()

        val url = URLBuilder(baseUrl).apply {
            appendPathSegments(*path)
            query.forEach { (name, value) -> parameters.append(name, value) }
        }.build()

        val response = try {
            httpClient.request(url) {
                this.method = method
                header("xi-api-key", key)
                if (jsonBody != null) setBody(TextContent(jsonBody, ContentType.Application.Json))
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: IOException) {
            throw ElevenLabsError.Network(error)
        }

        val body = response.bodyAsText()
        if (!response.status.isSuccess()) throw ElevenLabsError.from(response.status.value, body)
        return body
    }

    private fun <T> decode(strategy: DeserializationStrategy<T>, body: String): T = try {
        json.decodeFromString(strategy, body)
    } catch (_: SerializationException) {
        throw ElevenLabsError.Decoding()
    }

    public companion object {
        public const val DEFAULT_MODEL_ID: String = "eleven_multilingual_v2"
        internal const val OUTPUT_FORMAT = "mp3_44100_128"
        internal const val DEFAULT_BASE_URL = "https://api.elevenlabs.io"

        internal val json = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
        }

        private fun defaultHttpClient() = HttpClient {
            install(HttpTimeout) { requestTimeoutMillis = 120_000 }
        }
    }
}

/**
 * `String.localizedCaseInsensitiveCompare` from Foundation: the voice list is sorted the way the user's locale
 * expects. Common Kotlin has no collation, so each platform supplies its own.
 */
internal expect fun compareLocalizedCaseInsensitive(a: String, b: String): Int
