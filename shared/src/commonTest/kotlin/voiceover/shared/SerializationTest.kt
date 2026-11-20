package voiceover.shared

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import voiceover.shared.captions.Caption
import voiceover.shared.captions.TimedWord
import voiceover.shared.elevenlabs.Voice
import voiceover.shared.elevenlabs.VoiceSettings
import kotlin.test.Test
import kotlin.test.assertEquals

/** Port of `CodableTests.swift`, minus `Character`, which was not ported. */
class SerializationTest {
    @Test
    fun voiceAndSettingsRoundTrip() {
        val voice = Voice(
            voiceId = "v1",
            name = "Rachel",
            category = "premade",
            labels = mapOf("accent" to "american"),
            previewUrl = "https://example.com/r.mp3",
        )
        val settings = VoiceSettings(stability = 0.3, speed = 1.1)

        assertEquals(voice, Json.decodeFromString(Voice.serializer(), Json.encodeToString(Voice.serializer(), voice)))
        assertEquals(
            settings,
            Json.decodeFromString(VoiceSettings.serializer(), Json.encodeToString(VoiceSettings.serializer(), settings)),
        )
    }

    @Test
    fun wordsAndCaptionsRoundTrip() {
        val words = listOf(TimedWord("Hi", start = 0.1, end = 0.4))
        val captions = listOf(Caption(id = 3, text = "Hi", start = 0.1, end = 0.4, track = 1))
        val wordList = ListSerializer(TimedWord.serializer())
        val captionList = ListSerializer(Caption.serializer())

        assertEquals(words, Json.decodeFromString(wordList, Json.encodeToString(wordList, words)))
        assertEquals(captions, Json.decodeFromString(captionList, Json.encodeToString(captionList, captions)))
    }
}
