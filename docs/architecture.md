# Architecture

## Two layers, one direction

```
App (SwiftUI, iOS 26)  ──depends on──▶  VoiceoverKit (Swift package, no UI, no AVFoundation)
```

**VoiceoverKit** owns everything that can be reasoned about without a device: the ElevenLabs client and its
error model, the timeline maths (overlap resolution, caption assembly, caption line breaking) and the value
types they share (`Take`, `AudioSegment`, `Character`, `Voice`, `VoiceSettings`, `Caption`, `TimedWord`).
It builds in Swift 6 language mode with `swift test` on macOS, which is why nothing in it touches AVFoundation
or UIKit. Tests use a stub `HTTPTransport`, so no network.

**App** owns state, files, media and UI. AVFoundation, Speech, Photos and PhotosUI live only here.

## Folders

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
    Editor/      EditorView (+Helpers), EditorModel (+Recording, +Effects, +Jobs), Sections/
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

One type per file. A file named `X+Y.swift` is an extension of `X` grouping the `Y` concern; the members it
needs are `internal`, not `private`, on purpose.

## Who owns what

| Object | Lifetime | Owns |
|---|---|---|
| `AppModel` | app | `ElevenLabsClient`, `ProjectStore`, API-key presence; sets the playback audio session at launch |
| `ProjectStore` | app | the `Documents/Projects` folder and the list of summaries |
| `Project` | while its editor is open | all edit state: video, characters, takes, transcripts, converted audio, effects, mix, trim, type-mode result, export |
| `EditorModel` | while its editor is open | orchestration: the player, the composed edit, activity/failure, recorder, transcription tasks, autosaver, strip cache |
| `TakeRecorder` | per editor | `AVAudioRecorder`, live metering |
| `ProjectAutosaver` | per editor | observes `Project.document`, saves after 600 ms |
| `RecordingView` / `PreviewScreen` | presented | nothing: they read the model and call it |

`Project` is deliberately dumb: it mutates state, deletes files it no longer references and knows nothing
about AVFoundation, networking or Observation beyond being `@Observable`. `EditorModel` is the only place
that decides *when* to recompose, transcribe, swap or export.

That makes a rule for views: **views do not mutate `Project` except for presentation-only fields**
(`activeCharacterID`, `mix`, `script`, `voice` in Type mode). Anything that changes which audio is heard or
what the export covers (takes, characters and their voices, effects, trim, mode) goes through an `EditorModel`
method, which performs the mutation and then rebuilds captions, recomposes or drops the stale export. The
first version let `CharactersSection` delete a character straight on the project; its takes and files went,
the player kept an item pointing at them and the captions stayed.

## Data flow in a session

1. `ProjectListView` → tap → `ProjectScreen` sleeps 300 ms (lets the push animate), decodes the manifest in
   the background, builds `EditorModel(project:client:store:)`.
2. `EditorModel.init` → `restore()`: captions from stored transcripts, `recompose()` for a player, waveforms
   at utility priority. The autosaver starts observing.
3. **Record**: `RecordingView` → `startRecording()` (mute video, start recorder, play) → `stopRecording()`
   (add take, seek back, `rebuildCaptions`, `recompose`, `transcribe`, waveform).
4. **Swap**: `swapVoices()` → `VoiceSwapper` (≤3 requests in flight) → `project.setConvertedAudio` per take →
   `recompose`.
5. **Export**: `export()` → `VideoComposer.export` with the mix levels and trim range → `PhotosSaver`.
6. Every mutation of `Project` is picked up by the autosaver; the manifest is rewritten atomically.
7. Pop → `EditorModel` is released → `isolated deinit` cancels work, pauses the player, flushes the save.

## State machine

```
NoVideo ──setVideo──▶ Ready ──startRecording──▶ Recording ──stopRecording──▶ Ready
Ready ──swapVoices──▶ Swapping ──done/error──▶ Ready
Ready ──export──▶ Exporting ──done──▶ Saving(Photos) ──▶ Ready
Ready ──addEffect──▶ GeneratingEffect ──▶ Ready
Ready ──generate (Type mode)──▶ Generating ──▶ Ready
```

`EditorModel.activity` holds the current step; `run(_:slot:retry:operation:)` wraps each step so that an
`ElevenLabsError` turns into a `Failure` with a recovery (open settings / retry / edit input / none) and the
retry repeats *only that step*. Composing is also an activity so the UI can show "Updating preview…", but it
is cheap and frequent.

Work runs in one of two slots:

- **compose** — `recompose()`. Restartable: a newer compose cancels an older one.
- **job** — swap, export, generation, effect, Photos save. Spends credits or minutes, so nothing cancels it
  except the user's Cancel button. `isBusy` is true while a job runs; edits that would change the composition
  (delete a take, switch mode, remove an effect) are disabled in the UI and ignored by the model, and a
  `recompose()` requested meanwhile is deferred until the job finishes.

A job that needs the edit rebuilt at its end calls `compose(videoURL:)` directly rather than `recompose()`;
the latter would cancel the job's own slot.

`Failure.retry` re-enters the public method with plain values (`{ [weak self] in self?.export() }`), never the
operation closure. A failure is stored on the model, so a retry that captured the operation would hold `self`
through it and keep the editor alive after its screen was popped.

## Modes

`EditingMode.record` is the product; `.type` is the original script-to-speech flow kept as a secondary path.
They share the video, the player, the mix, the export and the effects lane; they differ in where the voice
comes from (takes vs. one generated speech file) and where captions come from (transcripts vs. character
timestamps).
