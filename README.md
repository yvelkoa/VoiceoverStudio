# Voiceover Studio

Add an AI voiceover, word-synced captions and a generated sound effect to any short video, powered by the
[ElevenLabs API](https://elevenlabs.io/docs).

<!-- TODO: demo GIF (pick clip → write script → choose voice → export) -->

**Flow:** pick a video from Photos → write a script → choose a voice → (optional) describe a sound effect →
preview with live captions → export an MP4 with captions burned in.

## Architecture

Two layers with a one-way dependency. The app owns UI, state and AVFoundation; `VoiceoverKit` owns the
network, parsing and caption maths, and has no UI imports, so it is tested with plain `swift test`.

```mermaid
flowchart LR
    subgraph App["App (SwiftUI, iOS 26, main actor by default)"]
        direction TB
        AppModel["AppModel<br/>API key presence, key verification"]
        EditorModel["EditorModel<br/>inputs, activity state, retry"]
        EditorView["EditorView<br/>Form: video / script / effect / result"]
        VoicePicker["VoicePickerView<br/>voice list + preview playback"]
        Settings["SettingsView<br/>enter / remove key"]
        Preview["PreviewPlayer<br/>AVPlayer + SwiftUI caption overlay"]
        Composer["VideoComposer (nonisolated)<br/>AVMutableComposition, audio mix,<br/>CATextLayer export"]
    end

    subgraph Kit["VoiceoverKit (Swift package, no UI)"]
        direction TB
        Client["ElevenLabsClient (actor)<br/>voices cache"]
        Transport["HTTPTransport<br/>URLSession in prod,<br/>stub in tests"]
        Captions["CaptionBuilder<br/>characters → words → captions"]
        Errors["ElevenLabsError<br/>typed + Recovery"]
        Keychain["KeychainStore"]
        Models["Voice, Speech,<br/>CharacterAlignment, Caption"]
    end

    EL[("ElevenLabs API")]

    EditorView --> EditorModel
    EditorView --> VoicePicker
    EditorView --> Settings
    EditorView --> Preview
    Settings --> AppModel
    AppModel --> Keychain
    AppModel --> Client
    EditorModel --> Client
    EditorModel --> Captions
    EditorModel --> Composer
    Client --> Transport --> EL
    Client --> Errors
```

### Generate flow

Voice and sound effect are requested in parallel. Generated audio is written to disk once, so moving the
effect on the timeline only re-composes and never calls the API again.

```mermaid
sequenceDiagram
    actor U as User
    participant V as EditorView
    participant M as EditorModel
    participant C as ElevenLabsClient
    participant B as CaptionBuilder
    participant X as VideoComposer
    participant P as PreviewPlayer

    U->>V: Generate voiceover
    V->>M: generate()
    activate M
    Note over M: activity = .generating
    par in parallel (async let)
        M->>C: speech(text, voiceID)
        C-->>M: Speech(audio, alignment)
    and
        M->>C: soundEffect(prompt)
        C-->>M: Data?
    end
    M->>M: write speech.mp3 / effect.mp3 to tmp
    M->>B: captions(from: alignment)
    B-->>M: [Caption]
    M->>X: compose(video, voice, effect, start)
    Note over X: off main actor (@concurrent)
    X-->>M: ComposedVideo (sending)
    M->>P: AVPlayerItem + captions
    deactivate M

    U->>V: move effect
    V->>M: applyEffectStart()
    M->>X: compose(...)
    Note over M,X: no network call
    X-->>M: ComposedVideo

    U->>V: Export
    V->>M: export()
    M->>X: export(composed, captions)
    Note over X: AVAssetExportSession +<br/>CoreAnimationTool burns captions
    X-->>M: MP4 URL
```

### Editor state

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Generating: generate()
    Generating --> Ready: composed
    Generating --> Idle: cancel / error (retry = generate)
    Ready --> Composing: applyEffectStart()
    Composing --> Ready: composed
    Ready --> Exporting: export()
    Exporting --> Exported: MP4 written
    Exporting --> Ready: error (retry = export only)
    Exported --> Composing: applyEffectStart()
    Ready --> Generating: generate() again
    Exported --> Generating: generate() again
    Ready --> Idle: setVideo()
    Exported --> Idle: setVideo()
```

`activity` is `nil` in Idle / Ready / Exported; a `Failure` carries the exact closure to retry, so an
export error never re-spends generation credits.

### Captions: two renderers, one source

```mermaid
flowchart LR
    A["with-timestamps response<br/>characters[], start[], end[]"] --> W["CaptionBuilder.words<br/>split on whitespace"]
    W --> L["CaptionBuilder.captions<br/>break at . ! ?<br/>or 32 chars or 3 s"]
    L --> CAP["[Caption]"]
    CAP --> O["Preview: SwiftUI Text overlay<br/>driven by periodic time observer"]
    CAP --> E["Export: one CATextLayer per caption<br/>opacity keyframes at start / end"]
```

## Engineering notes

- **Captions come from character timestamps, not guesswork.** The `with-timestamps` endpoint returns start and end
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
3. Run on an iOS 26+ simulator or device, open Settings and paste the key.

Tests: `swift test --package-path Packages/VoiceoverKit`

## Roadmap

- Streaming TTS over WebSocket, so playback starts before generation finishes
- Multiple voices (dialogue)
- Auto-ducking of the sound effect under speech
- Waveform timeline with drag to position the effect
