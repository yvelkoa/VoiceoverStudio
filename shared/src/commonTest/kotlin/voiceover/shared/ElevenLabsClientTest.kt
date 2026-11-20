package voiceover.shared

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.TextContent
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.io.IOException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import voiceover.shared.elevenlabs.ElevenLabsClient
import voiceover.shared.elevenlabs.ElevenLabsError
import voiceover.shared.elevenlabs.VoiceSettings
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Port of the voices, speech and error-mapping cases of `ElevenLabsClientTests.swift`. Ktor's `MockEngine`
 * plays the part of the Swift `MockTransport`. Sound effects, music and the voice changer are not ported, so the
 * error table goes through `voices()` instead of `soundEffect()`; the mapping under test is the same.
 */
class ElevenLabsClientTest {
    private class Response(val status: Int, val body: String)

    private fun mockEngine(vararg responses: Response, error: Throwable? = null): MockEngine {
        val queue = ArrayDeque(responses.toList())
        return MockEngine {
            if (error != null) throw error
            val next = queue.removeFirst()
            respond(next.body, HttpStatusCode.fromValue(next.status))
        }
    }

    private fun client(engine: MockEngine, apiKey: () -> String? = { "key" }) =
        ElevenLabsClient(HttpClient(engine), apiKey = apiKey)

    private fun MockEngine.jsonBody(index: Int = 0): JsonObject =
        Json.parseToJsonElement((requestHistory[index].body as TextContent).text) as JsonObject

    @Test
    fun voicesAreDecodedSortedAndCached() = runTest {
        val engine = mockEngine(Response(200, Fixtures.VOICES))
        val client = client(engine)

        val voices = client.voices()
        client.voices()

        assertEquals(listOf("adam", "Rachel"), voices.map { it.name })
        assertEquals(emptyMap(), voices[0].labels, "a non-string label must not break decoding")
        assertEquals("american · young · female · narration", voices[1].summary)
        assertEquals(1, engine.requestHistory.size)
        assertEquals("key", engine.requestHistory[0].headers["xi-api-key"])
    }

    @Test
    fun speechDecodesAudioAndAlignment() = runTest {
        val engine = mockEngine(Response(200, Fixtures.SPEECH))
        val client = client(engine)

        val speech = client.speech(text = "Hi there.", voiceId = "voice_a")

        assertContentEquals("ID3".encodeToByteArray(), speech.audio)
        assertEquals(9, speech.alignment.characters.size)
        val request = engine.requestHistory.first()
        assertEquals(HttpMethod.Post, request.method)
        assertEquals("/v1/text-to-speech/voice_a/with-timestamps", request.url.encodedPath)
        assertEquals("output_format=mp3_44100_128", request.url.encodedQuery)
        assertEquals(
            buildJsonObject {
                put("text", "Hi there.")
                put("model_id", ElevenLabsClient.DEFAULT_MODEL_ID)
            },
            engine.jsonBody(),
        )
    }

    @Test
    fun speechPassesVoiceSettingsWhenGiven() = runTest {
        val engine = mockEngine(Response(200, Fixtures.SPEECH))
        val client = client(engine)

        client.speech(text = "Hi", voiceId = "v", settings = VoiceSettings(stability = 0.3, speed = 1.1))

        assertEquals(
            buildJsonObject {
                put("stability", 0.3)
                put("speed", 1.1)
            },
            engine.jsonBody()["voice_settings"],
            "nil fields are omitted, keys use snake_case",
        )
    }

    @Test
    fun missingKeyFailsWithoutNetwork() = runTest {
        val engine = mockEngine()
        val client = client(engine) { null }

        assertEquals(ElevenLabsError.MissingApiKey(), assertFailsWith<ElevenLabsError> { client.voices() })
        assertTrue(engine.requestHistory.isEmpty())
    }

    @Test
    fun httpErrorsMapToTypedErrors() = runTest {
        val cases = listOf(
            Triple(401, """{"detail":{"status":"invalid_api_key","message":"Invalid"}}""", ElevenLabsError.InvalidApiKey()),
            Triple(401, """{"detail":{"status":"quota_exceeded","message":"Out"}}""", ElevenLabsError.QuotaExceeded()),
            Triple(
                401,
                """{"detail":{"status":"missing_permissions","message":"Missing the permission speech_to_speech."}}""",
                ElevenLabsError.MissingPermission("Missing the permission speech_to_speech."),
            ),
            Triple(429, """{"detail":{"status":"too_many_concurrent_requests"}}""", ElevenLabsError.RateLimited()),
            Triple(422, """{"detail":[{"msg":"text is too long"}]}""", ElevenLabsError.InvalidRequest("text is too long")),
            Triple(500, "oops", ElevenLabsError.Server(status = 500)),
        )
        for ((status, body, expected) in cases) {
            val client = client(mockEngine(Response(status, body)))

            assertEquals(expected, assertFailsWith<ElevenLabsError> { client.voices() }, "HTTP $status $body")
        }
    }

    @Test
    fun offlineMapsToNetworkError() = runTest {
        val client = client(mockEngine(error = IOException("offline")))

        val error = assertFailsWith<ElevenLabsError> { client.voices() }

        assertIs<ElevenLabsError.Network>(error)
        assertEquals(ElevenLabsError.Recovery.RETRY, error.recovery)
    }

    // Not in the Swift suite: the Swift client turns URLError.cancelled into CancellationError, and the Kotlin
    // one must likewise let cancellation through instead of reporting a network failure.
    @Test
    fun cancellationIsNotReportedAsNetworkError() = runTest {
        val client = client(mockEngine(error = CancellationException("cancelled")))

        assertFailsWith<CancellationException> { client.voices() }
    }

    // Not in the Swift suite: pins the rows of `ElevenLabsError.from` the table above leaves out.
    @Test
    fun remainingErrorRowsMatchTheSwiftSwitch() = runTest {
        val cases = listOf(
            Triple(403, """{"detail":{"status":"invalid_api_key"}}""", ElevenLabsError.InvalidApiKey()),
            Triple(
                403,
                """{"detail":{"status":"missing_permissions"}}""",
                ElevenLabsError.MissingPermission("The API key is missing a permission this feature needs."),
            ),
            Triple(400, "{}", ElevenLabsError.InvalidRequest("The request was rejected.")),
            Triple(400, """{"detail":{"status":7,"message":"ignored"}}""", ElevenLabsError.InvalidRequest("The request was rejected.")),
            Triple(503, """{"detail":null}""", ElevenLabsError.Server(status = 503)),
        )
        for ((status, body, expected) in cases) {
            val client = client(mockEngine(Response(status, body)))

            assertEquals(expected, assertFailsWith<ElevenLabsError> { client.voices() }, "HTTP $status $body")
        }
    }
}
