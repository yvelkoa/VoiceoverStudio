# Takes, characters and the timeline

> **At a glance**
> - A take is never edited on disk. `TakeResolver` computes the audible slices; everything downstream (composer,
>   captions, lanes) reads slices.
> - Within one character the **newest take wins** where they overlap. Characters never cut each other.
> - Live meter and stored waveform share one linear scale, so the trace does not change shape at Stop.
> - Two transcription engines behind one function, chosen by locale.
> - The scrubber is a `TimelineView`, not a `ScrollView`: position per frame from the player's clock.

## 1. Model

```mermaid
classDiagram
    class Character {
        id
        name
        voice: Voice?
        settings: VoiceSettings
        colorIndex
    }
    class Take {
        id
        characterID
        start
        duration
        recording: URL
        sequence
    }
    class AudioSegment {
        takeID
        characterID
        start
        sourceOffset
        duration
    }
    class SoundEffect {
        id
        prompt
        start
        duration
        audio: URL
    }
    Character "1" <-- "*" Take : characterID
    Take "1" <-- "0..2" AudioSegment : TakeResolver output
```

- `sequence` is the recording order and the only thing that decides precedence.
- `start` is where the user pressed Record on the timeline; `duration` is what the recorder measured at Stop.

## 2. Overlap resolution (`TakeResolver`, kit, tested)

```
timeline  0s        2s        4s        6s        8s
take 1    [=========================]              seq 1
take 2              [=========]                    seq 2 (punch-in)
result    [ t1 ---- ][ t2 ---- ][ t1 ][            3 segments
          off 0       off 0      off 4s
```

```mermaid
flowchart LR
    A[takes of one character] --> B[sort by sequence]
    B --> C["for each take: subtract ranges of every later take"]
    C --> D["0, 1 or 2 slices"]
    D --> E["drop slices &lt; 50 ms"]
    E --> F["AudioSegment(sourceOffset = slice.start − take.start)"]
    F --> G["sort all characters' segments by start"]
```

> **Decision.** Resolution is computed, never written back to files.
> **Why.** Nothing is destructive: deleting the newer take brings the older one back whole. The same resolution
> feeds the composer, the captions and the lanes, so they can never disagree.

## 3. Recording (`TakeRecorder`)

| Setting | Value |
|---|---|
| Format | AAC, 44.1 kHz, mono, high quality |
| File | `take-<uuid>.m4a` in the project folder |
| Permission | `AVAudioApplication.requestRecordPermission()` |
| Metering | `peakPower` sampled every 20 ms (`Waveform.bucket`) |
| Minimum length | `TakeResolver.minimumDuration`; shorter takes are discarded and their file deleted |

```mermaid
flowchart LR
    T["metering tick (may run late)"] --> C["recorder.currentTime / bucket"]
    C --> F["fill liveLevels up to that index"]
    F --> S["strip draws live segment<br/>aligned with the playhead"]
```

> **Decision.** `liveLevels` is filled **up to the recorder's own clock**, not by tick count.
> **Why.** When the timer runs late the trace used to lag behind the playhead. Filling by clock keeps them aligned.

Double-tap protection: `start(in:)` refuses while a recorder exists, and `EditorModel.isStartingRecording` covers
the gap while the microphone prompt is up. Otherwise the first recorder kept metering into `liveLevels` with no one
to stop it.

**End of the video.** A take ends by itself when the video does: `RecordingSession` holds a `PlaybackEndWatcher`
while recording, and the model stops the take as if Stop had been pressed on the last frame. Record pressed within
half a second of the end rewinds to the start first.

> **Decision.** The watcher listens to every `didPlayToEndTime` and compares the item with the player's *current*
> one when it fires.
> **Why.** A recompose finishing just after Record swaps the player's item; an observer bound to the old item
> would never fire and the take would run on over a frozen frame, as it did before.

## 4. Waveforms (`Waveform`)

| Source | Conversion |
|---|---|
| Stored file | `AVAssetReader` → 16 kHz mono 16-bit PCM → peak per 20 ms bucket → linear × 1.6, clipped to 1 |
| Live meter | dBFS → `Waveform.level(fromDecibels:)` → same linear scale |

> **Decision.** One scale for both.
> **Why.** Earlier the live meter was dB-linear and the stored waveform was normalised to its own maximum. The trace
> changed shape the moment Stop was pressed.

Waveforms are not persisted; they are recomputed at utility priority when a project opens.
`levels(from:duration:count:)` resamples a slice for drawing, so a split take draws the right part.

## 5. Transcription (`Transcriber`)

```mermaid
flowchart TD
    W["Transcriber.words(in:locale:)"] --> Q{SpeechTranscriber<br/>supports locale?}
    Q -->|"en, de, fr, es, it, pt, ja, ko, zh"| OD["SpeechAnalyzer + SpeechTranscriber<br/>on device"]
    Q -->|"else, incl. ru, uk"| SF["SFSpeechRecognizer<br/>Apple servers, ~1 min cap"]
    OD --> R["[TimedWord] from audioTimeRange attributes"]
    SF --> R
```

Things that cost time to learn:

1. Call `AssetInventory.reserve(locale:)` **before** `assetInstallationRequest`, or the request fails with
   "not subscribed to transcription.en".
2. `analyzeSequence(from:)` + `finalizeAndFinish(through:)` leaves `transcriber.results` open forever. Use
   `start(inputAudioFile:finishAfterFile: true)`. Verified with synthesized speech.
3. `SFTranscription` is not `Sendable`: convert to `[TimedWord]` *inside* the callback.
4. A lock-guarded `ResumeOnce` protects the continuation from a second callback.
5. `withTaskCancellationHandler` cancels the `SFSpeechRecognitionTask` with the Swift task (deleted take, closed
   editor). Otherwise the request kept streaming to the server for up to a minute.

The recording language is a setting (`RecordingLanguage`, UserDefaults), defaulting to the device locale.

## 6. Captions from takes (`CaptionAssembler`, kit, tested)

```mermaid
flowchart LR
    S[AudioSegment] --> W["words of its take with<br/>start inside the slice"]
    W --> SH["shift by segment.start − sourceOffset"]
    SH --> G[group per character]
    G --> B["CaptionBuilder: break at . ! ?<br/>or 32 chars or 3 s"]
    B --> C["Caption(track = character index)"]
```

Two people talking at once render on two lines because each character has its own `track`. Ids are unique across
characters.

## 7. Voice swap (`VoiceSwapper`)

```mermaid
sequenceDiagram
    participant M as EditorModel.swapVoices
    participant S as VoiceSwapper (≤3 in flight)
    participant X as ElevenLabs voice-changer
    participant P as Project
    M->>S: takes needing conversion
    par up to three at once
        S->>X: take A
        S->>X: take B
        S->>X: take C
    end
    X-->>S: MP3 per take
    S-->>P: setConvertedAudio(take, url, drift) on main actor, one by one
    M->>M: compose at the end
```

> **Decision.** Each take is sent separately.
> **Why.** Cheaper than one flattened file (no silence billed), and a retry re-sends one take, not all.

The converted MP3 replaces the recording in `voiceClips()`. The length difference is `conversionDrift`, flagged
above 150 ms because captions are timed from the recording. Changing a character's voice or settings invalidates
only that character's conversions.

## 8. The scrubber (`TimelineStrip`)

A Photos-style strip: content slides under a fixed playhead.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Scrubbing: drag of 4 pt or more
    Scrubbing --> Coasting: release with velocity
    Coasting --> Idle: velocity near 0, or hits an end
    Coasting --> Scrubbing: new touch
    Scrubbing --> Idle: release without velocity
    Idle --> Playing: player rate above 0
    Playing --> Idle: pause or stop
    Idle --> Idle: tap seeks
```

| State | Source of position |
|---|---|
| Scrubbing | finger translation 1:1 to time, `pointsPerSecond = 56` |
| Coasting | `coast(velocity:)`, UIScrollView's curve: ×0.998 per ms, stepped at 120 Hz |
| Playing | `TimelineView(.animation)` reads `player.currentTime()` every display frame |
| Idle | `currentTime` passed in by the owner after seeks, stops, first appearance |

Seeks issued while scrubbing are **coalesced** in `RecordingView`: one in flight, only the newest pending time is
honoured, tolerance 1/30 s. Without that a 60 fps clip lagged behind the finger.

> **Decision.** `TimelineView` + `.offset`, not `ScrollView` + `ScrollPosition`.
> **Why.** The scroll version animated one long linear scroll during playback. Smooth, but the animation outlived a
> pause and the strip kept moving after a take stopped. `TimelineView` has no such state.

Lanes: one per character in declaration order with the resolved segments (tinted block + waveform, identified by
the whole `AudioSegment` value), a live segment in full colour while recording, one Effects lane with prompt text.
The trim range is shown by dimming the strip outside it.
