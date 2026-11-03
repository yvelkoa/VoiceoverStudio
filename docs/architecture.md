# Architecture

> **At a glance**
> - Two layers, one direction: **App** (SwiftUI, iOS 26) depends on **VoiceoverKit** (pure Swift, tested on macOS).
> - `Project` holds the edit and is deliberately dumb. `EditorModel` is the only orchestrator.
> - Views never mutate anything that changes what is heard; they call `EditorModel`.
> - Work runs in two slots, **compose** (cheap, restartable) and **job** (billed, never cancelled by accident).

## 1. Layers

```mermaid
flowchart TB
    subgraph App["App target (SwiftUI, iOS 26)"]
        direction TB
        UI["Features: views"]
        EM[EditorModel + extensions]
        P[Project]
        Media["Media: composer, recorder, transcriber, swapper"]
        Store["Persistence: store, document, autosaver"]
        UI --> EM --> P
        EM --> Media
        EM --> Store
    end
    subgraph Kit["VoiceoverKit (no UI, no AVFoundation)"]
        direction TB
        EL[ElevenLabsClient + errors]
        TL["Timeline: Take, TakeResolver, Character"]
        CP["Captions: CaptionBuilder, CaptionAssembler"]
        KC[KeychainStore]
    end
    App --> Kit
```

| Layer | Owns | Must not contain |
|---|---|---|
| **VoiceoverKit** | ElevenLabs client and error model, timeline maths (overlap resolution, caption assembly, line breaking), shared value types (`Take`, `AudioSegment`, `Character`, `Voice`, `VoiceSettings`, `Caption`, `TimedWord`), Keychain | AVFoundation, UIKit, SwiftUI, file-system layout |
| **App** | State, files, media, UI. AVFoundation, Speech, Photos, PhotosUI | Business rules that could be tested without a device |

The kit builds in Swift 6 language mode and is tested with `swift test` on macOS, with a stub `HTTPTransport`
instead of the network. That is the reason the boundary is where it is: anything that needs a simulator to test
stays in the app.

## 2. Folders

```
App/
  App/           VoiceoverStudioApp (entry), AppModel (API key, store, client), APIKeyStore
  Models/        Project (the edit), SoundEffect, LiveRecording
  Persistence/   ProjectDocument (on-disk shape), ProjectStore, ProjectAutosaver, ProjectSummary, EditingMode
  Media/
    Composition/ VideoComposer, ComposedVideo, AudioClip + AudioKind, MixLevels
    Recording/   TakeRecorder, Waveform, AudioSession
    Speech/      Transcriber, RecordingLanguage
    Video/       FrameStrip, Thumbnail, PhotosSaver, PickedMovie
    ElevenLabs/  VoiceSwapper
  Features/
    Projects/    ProjectListView (root), ProjectRow, ProjectScreen (loads a project, owns its EditorModel)
    Editor/      EditorView (+Helpers), EditorModel (+Recording, +Effects, +Jobs), WorkRunner, EditPlayer, Sections/
    Recording/   RecordingView (full-screen recorder), EffectSheet, MixPopover, Timeline/{TimelineStrip, SegmentView}
    Preview/     PreviewScreen, PreviewPlayer, CaptionOverlay, PlayerLayerView, AVPlayer+TimeUpdates
    Settings/    SettingsView
    Voices/      VoicePickerView
Packages/VoiceoverKit/Sources/VoiceoverKit/
  ElevenLabs/    ElevenLabsClient, ElevenLabsError, HTTPTransport, MultipartForm, Voice, Speech, VoiceSettings
  Timeline/      Take, AudioSegment, TakeResolver, Character
  Captions/      TimedWord, Caption, CaptionBuilder, CaptionAssembler
  Keychain/      KeychainStore
```

Conventions:

- One type per file.
- `X+Y.swift` is an extension of `X` grouping the `Y` concern. Members it needs are `internal`, not `private`,
  on purpose.

## 3. Who owns what

```mermaid
flowchart LR
    AppModel -->|owns| Client[ElevenLabsClient]
    AppModel -->|owns| Store[ProjectStore]
    ProjectScreen -->|"@State, one per push"| EditorModel
    EditorModel -->|owns| Project
    EditorModel -->|owns| Recorder[TakeRecorder]
    EditorModel -->|owns| Autosaver[ProjectAutosaver]
    EditorModel -->|owns| Player[AVPlayer]
    EditorModel -->|owns| Composed[ComposedVideo]
    Autosaver -->|observes| Project
    Autosaver -->|writes via| Store
    RecordingView -->|reads, calls| EditorModel
    PreviewScreen -->|reads| Player
```

| Object | Lifetime | Owns |
|---|---|---|
| `AppModel` | app | `ElevenLabsClient`, `ProjectStore`, API-key presence; sets the playback audio category at launch |
| `ProjectStore` | app | the `Documents/Projects` folder and the list of summaries |
| `Project` | while its editor is open | all edit state: video, characters, takes, transcripts, converted audio, effects, mix, trim, Type-mode result, export |
| `EditorModel` | while its editor is open | orchestration: player, composed edit, activity and failure, recorder, transcription tasks, autosaver, strip cache |
| `TakeRecorder` | per editor | `AVAudioRecorder`, live metering |
| `ProjectAutosaver` | per editor | observes `Project.document`, saves after 600 ms |
| `RecordingView`, `PreviewScreen` | while presented | nothing; they read the model and call it |

### The one rule for views

> **Decision.** Views do not mutate `Project` except for presentation-only fields: `activeCharacterID`, `mix`,
> `script`, `voice` in Type mode. Everything that changes what is heard or what the export covers (takes,
> characters and their voices, effects, trim, mode) goes through an `EditorModel` method.
> **Why.** The model must follow the mutation with `rebuildCaptions()`, `recompose()` or dropping the stale export.
> The first version let `CharactersSection` delete a character straight on the project: its takes and files went,
> the player kept an item pointing at them and the captions stayed.
> **Rejected.** Having `EditorModel` observe `project.segments` and react. Implicit, and it cannot know *which*
> follow-up (captions, recompose, export reset) the change needs.

`Project` mutates state, deletes files it no longer references, and knows nothing about AVFoundation, networking
or Observation beyond being `@Observable`.

## 4. A session, end to end

```mermaid
sequenceDiagram
    actor U as User
    participant L as ProjectListView
    participant S as ProjectScreen
    participant M as EditorModel
    participant R as RecordingView
    participant X as ElevenLabs

    U->>L: tap project
    L->>S: push
    S->>S: sleep 300 ms (let the push animate)
    S->>S: decode manifest off-main
    S->>M: init(project, client, store)
    M->>M: restore(): captions, recompose, waveforms
    U->>R: Record
    R->>M: startRecording()
    Note over M: mute player, start recorder, play
    U->>R: Stop
    R->>M: stopRecording()
    Note over M: add take, seek back, captions, recompose, transcribe
    U->>M: swapVoices()
    M->>X: voice-changer per take (≤3 in flight)
    X-->>M: converted audio
    M->>M: recompose
    U->>M: export()
    M->>M: VideoComposer.export → PhotosSaver
    U->>S: pop
    S-->>M: released → isolated deinit
    Note over M: cancel tasks, pause player, flush autosave
```

Every mutation of `Project` along the way is picked up by the autosaver and the manifest is rewritten
atomically (see [persistence.md](persistence.md)).

## 5. Activities, slots and the state machine

```mermaid
stateDiagram-v2
    [*] --> NoVideo
    NoVideo --> Ready: setVideo
    Ready --> Recording: startRecording
    Recording --> Ready: stopRecording or interruption
    Ready --> Swapping: swapVoices
    Swapping --> Ready: done, error or cancel
    Ready --> Exporting: export
    Exporting --> Saving: exported
    Saving --> Ready: added to Photos
    Ready --> GeneratingEffect: addEffect
    GeneratingEffect --> Ready
    Ready --> Generating: generate, Type mode
    Generating --> Ready
    note right of Ready
        Composing runs inside Ready
        as a cheap, restartable activity
    end note
```

`EditorModel.activity` holds the current step. `run(_:slot:retry:operation:)` wraps each step so that an error
becomes a `Failure` with a recovery (open settings, retry, edit input, none) and **the retry repeats only that
step**.

### Two slots

| Slot | Runs | Cancellation | Why separate |
|---|---|---|---|
| **compose** | `recompose()` | A newer compose cancels an older one | Cheap and frequent; restarting is fine |
| **job** | swap, export, generate, effect, Photos save | Only the user's Cancel button | Spends credits or minutes; a cancelled swap is already billed |

Consequences:

- `isBusy` is true while a job runs. Edits that would change the composition (delete a take, switch mode, remove
  an effect) are disabled in the UI and ignored by the model.
- A `recompose()` requested during a job is deferred (`needsRecompose`) and runs when the job finishes.
- A job that needs the edit rebuilt at its end calls `compose(videoURL:)` directly. Calling `recompose()` would
  cancel the job's own slot.

> **Decision.** `Failure.retry` re-enters the public method with plain values
> (`{ [weak self] in self?.export() }`), never the operation closure.
> **Why.** A failure is stored on the model. A retry that captured the operation would capture `self` through it,
> and the editor would never deinit after its screen was popped.

## 6. Modes

```mermaid
flowchart LR
    subgraph Shared
        V[video] --- PL[player] --- MX[mix] --- EX[export] --- EF[effects lane]
    end
    R["Record mode (the product)"] -->|voice from| T[takes]
    R -->|captions from| TR[transcripts]
    Y["Type mode (secondary)"] -->|voice from| G[one generated speech file]
    Y -->|captions from| TS[TTS character timestamps]
```

`EditingMode.record` is the product; `.type` is the original script-to-speech flow kept as a secondary path. They
share the video, the player, the mix, the export and the effects lane.
