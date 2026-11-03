# Voiceover Studio

Record a voiceover over any short video in your own voice, then swap it for an ElevenLabs voice. Timing,
pauses and delivery stay yours; captions follow the words. Several characters can talk, even over each
other. Powered by the [ElevenLabs API](https://elevenlabs.io/docs) and on-device speech recognition.

<!-- TODO: demo GIF (pick clip → record takes → swap voices → export) -->

**Record mode:** pick a video → add characters and give each a voice → scrub to a moment, press Record,
speak, stop; repeat per line and per character → Swap voices → preview with live captions → export an
MP4 with captions burned in.

**Type mode:** write a script, pick a voice, optionally describe a sound effect, generate, export.

## Architecture

Two layers with a one-way dependency. The app owns UI, state, recording and AVFoundation; `VoiceoverKit`
owns the network, parsing and the pure timeline maths (overlap resolution, caption assembly), has no UI
imports and is tested with plain `swift test`.

```mermaid
flowchart LR
    subgraph App["App (SwiftUI, iOS 26, main actor by default)"]
        direction TB
        EditorView["EditorView<br/>Record / Type switch"]
        EditorModel["EditorModel<br/>orchestration, activity, retry"]
        Project["Project<br/>video, characters, takes,<br/>transcripts, converted audio"]
        Recorder["TakeRecorder<br/>AVAudioRecorder → .m4a"]
        Transcriber["Transcriber<br/>SpeechTranscriber (on device)<br/>or SFSpeechRecognizer"]
        Swapper["VoiceSwapper<br/>≤3 requests in flight"]
        Composer["VideoComposer (nonisolated)<br/>clips → tracks, CATextLayer export"]
        Preview["PreviewPlayer<br/>caption overlay per track"]
    end

    subgraph Kit["VoiceoverKit (Swift package, no UI)"]
        direction TB
        Client["ElevenLabsClient (actor)<br/>voices · TTS · voice changer · SFX"]
        Resolver["TakeResolver<br/>newest take wins per character"]
        Assembler["CaptionAssembler<br/>words → timeline → tracks"]
        Captions["CaptionBuilder"]
        Errors["ElevenLabsError + Recovery"]
        Models["Character, Take, AudioSegment,<br/>Voice, VoiceSettings, Caption"]
    end

    EL[("ElevenLabs API")]
    Apple[("Apple speech models<br/>on device / server")]

    EditorView --> EditorModel
    EditorView --> Preview
    EditorModel --> Project
    EditorModel --> Recorder
    EditorModel --> Transcriber --> Apple
    EditorModel --> Swapper --> Client --> EL
    EditorModel --> Composer
    Project --> Resolver
    EditorModel --> Assembler --> Captions
    Client --> Errors
```

### Record flow

```mermaid
sequenceDiagram
    actor U as User
    participant M as EditorModel
    participant R as TakeRecorder
    participant P as Project
    participant T as Transcriber
    participant S as VoiceSwapper
    participant C as ElevenLabsClient
    participant X as VideoComposer

    U->>M: Record (playhead at 12.0 s)
    M->>R: start()
    Note over M: video plays muted
    U->>M: Stop
    M->>R: stop() → 4.2 s
    M->>P: addTake(character, start 12.0, 4.2 s)
    M->>X: compose(resolved segments)
    Note over M: raw voice audible in preview
    M-)T: words(in: take)
    T--)M: [TimedWord]
    M->>P: setTranscript
    M->>M: captions = CaptionAssembler(...)

    U->>M: Swap voices · 17 s
    M->>S: convert(jobs)
    par up to 3 at once
        S->>C: changeVoice(audio, voiceID, settings)
        C-->>S: MP3
    end
    S-->>M: outcome(takeID, url, drift)
    M->>P: setConvertedAudio
    M->>X: compose(converted segments)

    U->>M: Export
    M->>X: export(composed, captions)
    X-->>M: MP4 URL
```

### Takes, characters and overlap

```mermaid
gantt
    dateFormat ss
    axisFormat %S s
    title Two characters, one redo. Narrator's second take replaces the overlap; the dog is untouched.
    section Narrator
    take 1 (seq 1)        :a1, 00, 10s
    take 3 (seq 3, redo)  :crit, a3, 06, 6s
    section Dog
    take 2 (seq 2)        :b1, 04, 3s
    section Heard
    Narrator take 1 [0–6) :done, h1, 00, 6s
    Narrator take 3 [6–12) :done, h3, 06, 6s
    Dog take 2 [4–7)      :done, h2, 04, 3s
```

`TakeResolver` applies "newest take wins" only within a character. Each surviving slice becomes an
`AudioClip` on its own track, so characters can overlap like a real dialogue. Converted audio keeps the
take's timing, so the same offsets apply before and after the swap.

### Editor state

```mermaid
stateDiagram-v2
    [*] --> NoVideo
    NoVideo --> Ready: setVideo() → compose (raw video)
    Ready --> Recording: startRecording()
    Recording --> Ready: stopRecording() → take added, compose, transcribe
    Ready --> Swapping: swapVoices()
    Swapping --> Ready: all takes converted, compose
    Swapping --> Ready: error (retry = swap remaining takes)
    Ready --> Exporting: export()
    Exporting --> Ready: MP4 written / error (retry = export only)
    Ready --> Ready: delete take / move effect / change voice → compose
```

Transcription runs beside the state machine, one task per take; a failed transcription offers a retry
without touching the audio. A voice change on a character invalidates only that character's conversions.

### Captions: one source, two renderers

```mermaid
flowchart LR
    A["Take recording"] --> T["Transcriber<br/>words + time ranges"]
    T --> S["CaptionAssembler<br/>shift by segment start,<br/>drop words cut by a redo,<br/>track = character index"]
    TTS["TTS with-timestamps<br/>characters[], start[], end[]"] --> W["CaptionBuilder.words"]
    W --> L
    S --> L["CaptionBuilder.captions<br/>break at . ! ? / 32 chars / 3 s"]
    L --> CAP["[Caption] with track"]
    CAP --> O["Preview: SwiftUI overlay,<br/>one line per visible track"]
    CAP --> E["Export: CATextLayer per caption,<br/>y offset by track"]
```

## Engineering notes

- **Your timing, their voice.** Speech-to-speech keeps the pauses, emphasis and pace of the recording, so
  there is no script-to-timeline problem to solve: you just talk over the video. The app checks the
  converted length against the take and flags drift above 150 ms, because captions are timed from the
  recording.
- **Speech recognition picks the engine per language.** `SpeechTranscriber` (iOS 26) runs on device
  but covers English, German, French, Spanish, Italian, Portuguese, Japanese, Korean and Chinese only.
  Other languages, Russian included, go through `SFSpeechRecognizer`, which may use Apple's servers.
  One `Transcriber` hides the choice.
- **Credits are spent on purpose.** Nothing calls ElevenLabs until you press Swap voices, the button
  says how many seconds it will bill, and only takes without a current conversion are sent. Changing a
  character's voice invalidates just that character.

- **TTS captions come from character timestamps, not guesswork.** The `with-timestamps` endpoint returns start and end
  times for every character. `CaptionBuilder` groups them into words, then into short lines. Lines break at sentence
  punctuation, at 32 characters or at 3 seconds, so captions are always readable and in sync with the voice.
- **One edit, two renderers.** `AVVideoCompositionCoreAnimationTool` only works for offline export. The preview
  therefore draws the same captions as a SwiftUI overlay, driven by the player's time, and the export burns them in
  with `CATextLayer`s. Both read the same `[Caption]`.
- **Parallel requests.** Voice and sound effect don't depend on each other, so they are fetched with `async let`.
  Generated audio is kept on disk, so moving the sound effect on the timeline only re-composes and never calls the
  API again.
- **Errors you can act on.** HTTP and network failures map to `ElevenLabsError`: invalid key, quota, rate limit,
  validation, server, offline. Each case carries a user-facing message and a recovery action (open Settings, retry,
  edit input). A retry repeats only the step that failed, so retrying an export doesn't spend credits.
- **Swift 6 strict concurrency.** Main-actor-by-default isolation in the app; the networking client is an
  actor that owns the voice cache; the package builds in Swift 6 language mode.
- **Bring your own key.** No key in the bundle or the repo. The key is entered once, verified with a cheap request
  and stored in the Keychain (`AfterFirstUnlockThisDeviceOnly`).

## Run it

1. Get an API key at elevenlabs.io → Developers → API Keys. The free tier is enough. Text to Speech, Voices and
   Sound Effects permissions are all you need.
2. `brew install xcodegen && xcodegen generate && open VoiceoverStudio.xcodeproj`
3. Run on an iOS 26+ simulator or device, open Settings and paste the key. Pick the recording language
   there too if it differs from the device language.

Tests: `swift test --package-path Packages/VoiceoverKit`. Lint: `swiftlint lint --strict`.

## Roadmap

- Timeline strip: frame thumbnails, one lane per character, drag to move a take
- Trim silence at the edges of a take
- Remove filler words via on-device Foundation Models, cutting the audio by word timing
- Hear other characters' takes while recording a reply
- Auto-ducking of the sound effect under speech
