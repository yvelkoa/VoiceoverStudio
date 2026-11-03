# ElevenLabs integration

All calls go through `ElevenLabsClient` (kit, an actor). The key is read lazily through a closure from the
Keychain (`APIKeyStore`), so a key change needs no new client. Nothing is called until the user presses a
button that says it will cost credits.

## Endpoints

| Call | Endpoint | Used by |
|---|---|---|
| `voices(forceRefresh:)` | `GET /v1/voices` | voice picker, key verification; cached in the actor |
| `speech(text:voiceID:modelID:settings:)` | `POST /v1/text-to-speech/{id}/with-timestamps` | Type mode; returns MP3 + per-character times |
| `changeVoice(audio:fileName:mimeType:voiceID:modelID:settings:removeBackgroundNoise:)` | `POST /v1/voice-changer/{id}` (multipart) | voice swap of takes |
| `soundEffect(prompt:durationSeconds:)` | `POST /v1/sound-generation` | effects lane |

Models: `eleven_multilingual_v2` for TTS, `eleven_multilingual_sts_v2` for the voice changer. Output format
`mp3_44100_128` everywhere.

## Key permissions

The key needs **Text to Speech, Speech to Speech (Voice Changer), Voices, Sound Effects**. A key missing one
of them gets HTTP 401 with `detail.status = "missing_permissions"`; the client maps that to
`ElevenLabsError.missingPermission(message)` and shows the server's message, which names the permission. A
plain 401 or `invalid_api_key` is `.invalidAPIKey`. Mixing the two up cost a debugging session.

## Error model

`ElevenLabsError` cases carry a `Recovery`: `.openSettings` (key problems), `.retry` (rate limit, server,
network), `.editInput` (validation), `.none` (quota, permission, decoding). `EditorModel.Failure` turns
that into the alert's buttons; the retry closure re-runs only the failed step.

## Voice settings

`VoiceSettings { stability, similarityBoost, style, speed, useSpeakerBoost }`, all optional, encoded with
snake_case keys. Two presets: `.narration` (stable) and `.expressive` (stability 0.3, style 0.4), the
latter is the default for voice conversion so the result follows the recording's delivery.

## Credits

- TTS: one credit per character of script.
- Voice changer: billed by audio length; the Swap button shows the seconds it will send, only takes without
  a current conversion are sent, and a changed voice invalidates just that character.
- Sound effects: billed per generated second; the sheet says so; one request per effect, kept forever.

## Timing after a swap

Speech-to-speech preserves pace closely but not exactly. After each conversion the output length is
compared with the recording; the difference is `conversionDrift`. Above 150 ms the take is flagged in the
list and the timeline, because captions are timed from the original recording.

## Multipart

`MultipartForm` is a 40-line encoder; the test asserts the exact body layout including the boundary
terminator and that the binary audio is embedded unchanged.
