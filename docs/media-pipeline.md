# Media pipeline

Everything here is in `App/Media/Composition` and `App/Features/Preview`.

## One edit, two consumers

```
Project ──▶ EditorModel.compose ──▶ VideoComposer.compose(video:clips:) ──▶ ComposedVideo
                                                                             ├─▶ AVPlayerItem (preview)
                                                                             └─▶ AVAssetExportSession (export)
```

`ComposedVideo` holds:

- `composition: AVMutableComposition` — the video track plus one audio track per clip;
- `trackKinds: [CMPersistentTrackID: AudioKind]` — which track is original audio, voice or effect;
- `videoConfiguration: AVVideoComposition.Configuration` — a value type, used only by the export.

Preview and export are built from the same composition, so what you hear is what you get, with one
difference described under *Preview without a video composition*.

## Clips and tracks

`AudioClip(url:kind:start:sourceOffset:duration:)` is the composer's input. Each clip becomes its own
`AVMutableCompositionTrack`, which is what lets takes of different characters overlap and lets the effects
lane play under speech. A clip that would start past the video's end, or whose file has no audio track, is
skipped silently; audio past the end of the video is trimmed to it.

The sources of clips (`EditorModel.voiceClips/effectClips`):

- Record mode: every `AudioSegment` from `TakeResolver`, pointing at the take's recording or, if present,
  its converted audio. Converted audio keeps the take's timing, so the same `sourceOffset`/`duration` apply
  (see `conversionDrift` in [elevenlabs.md](elevenlabs.md) for when it doesn't quite).
- Type mode: one clip, the generated speech file, at 0.
- Both: one clip per `SoundEffect`.

## The live mix

Levels are not baked into the composition. `ComposedVideo.audioMix(_ levels: MixLevels)` builds a fresh
`AVMutableAudioMix` from `trackKinds` on demand, which costs nothing, so:

- a slider sets `player.currentItem?.audioMix` immediately (`EditorModel.applyMix`), no recompose;
- the export gets `audioMix(levels)` with the same values.

`MixLevels` defaults: original 0.25 (ducked under speech), voice 1.0, effects 0.8. When the composition has
no voice or effect tracks the preview plays the original at 1.0 so a freshly picked video sounds normal
(`EditorModel.previewLevels`, applied both on compose and from the sliders); the export takes the mix as set.

## Preview without a video composition

The preview `AVPlayerItem` deliberately has **no** `videoComposition`:

- `AVPlayer` applies the composition track's `preferredTransform` itself, so phone footage is upright;
- captions are a SwiftUI overlay (`CaptionOverlay`) driven by the player's time, not burned pixels;
- in the iOS Simulator, frames produced by the video compositor never reach `AVPlayerLayer`: the log
  shows `IQ-CA signalled err=-19230` and the picture is black. Headless playback and `AVAssetReader` work,
  only the display path fails. Dropping the composition from the preview sidesteps it and is also the
  cheaper path on device.

The compositor is only used by the export, where it is needed for the caption layers.

## Export

`VideoComposer.export(_:captions:levels:range:to:)`:

1. Takes the stored `videoConfiguration` (a value), adds an `AVVideoCompositionCoreAnimationTool` whose
   parent layer holds one `CATextLayer` per caption. Each layer has `opacity 0` and a `CABasicAnimation`
   from `AVCoreAnimationBeginTimeAtZero + start` lasting `end - start`, which is how a layer is visible only
   during its caption. Layers for `track > 0` are offset upwards by one line so simultaneous speakers stack.
2. Creates an `AVAssetExportSession` with `AVAssetExportPresetHighestQuality`, sets the video composition,
   the audio mix and, if trimmed, `timeRange`. Caption times are composition times, so trimming shifts
   nothing.
3. Exports MP4 into the project folder; `PhotosSaver` then adds it to the library with add-only access.

### Why the video composition is built by hand

The obvious call, `AVVideoComposition.Configuration(for: composition)`, **ignores the composition track's
`preferredTransform`**. For a portrait iPhone clip (stored as 1920×1080 rotated 90°) it produced a
1920×1080 render with the picture in one half of the frame and black in the other. Reproduced with a
synthetic rotated clip: 44% of the frame dark.

`VideoComposer.videoConfiguration(for:naturalSize:transform:frameRate:range:)` therefore does what the
system should: render size = natural size transformed by `preferredTransform` (absolute, rounded); one
instruction over the full range with one layer instruction whose transform is `preferredTransform`
concatenated with a translation by `-bounds.minX, -bounds.minY`, so the rotated picture starts at the
origin. Frame duration is `1/nominalFrameRate` (min 24). Verified full-frame on rotated, unrotated and
HLG HDR sources.

The composition track still gets `preferredTransform` because the preview, which has no video
composition, relies on it.

## Captions: one source, two renderers

| | Preview | Export |
|---|---|---|
| Renderer | `CaptionOverlay` (SwiftUI `Text`) | `CATextLayer` per caption |
| Timing | `AVPlayer.timeUpdates(every:)` → filter `start ≤ t < end` | opacity animation on the composition timeline |
| Stacking | `VStack`, sorted by `track` | y offset = `track × line height` |
| Style | title3 bold, white, shadow | system bold 5.5% of min(width,height), white, shadow |

Both read the same `[Caption]` from `EditorModel.captions`, which is rebuilt by `CaptionAssembler` (record
mode) or taken from the TTS alignment (type mode).

## Audio session

`AudioSession.configurePlayback()` sets the `.playback / .moviePlayback` **category** at launch without
activating the session: activating would stop the user's music the moment the project list appears, and
AVPlayer activates the session itself when it starts playing. `activatePlayback()` (category + active) runs
after every take; `activateRecording()` sets `.playAndRecord` with speaker output and Bluetooth HFP while a
take runs. The system default category obeys the silent switch, which made a relaunched app play the edit
without sound until the first recording changed categories.

While a take runs, `TakeRecorder` observes the session: an interruption (`.began`: call, Siri, alarm) or a
route change with `.oldDeviceUnavailable` (headset unplugged) calls `onInterruption`, which `EditorModel`
wires to `stopRecording()`, so what was recorded becomes a take instead of leaving REC over a recorder the
system has already stopped. `RecordingView` does the same when the scene goes to the background: there is no
background audio mode, so the recorder would stop anyway.

## Recording while the video plays

`startRecording` mutes the player (so the microphone doesn't pick up the soundtrack), remembers the
playhead as the take's start, starts `AVAudioRecorder` and then `play()`. `stopRecording` sets `rate = 0`,
unmutes, stops the recorder, adds the take and seeks back to the take's start. Hearing other characters'
earlier takes while recording a reply is on the roadmap; it needs echo cancellation or headphones.

## Frame strip and thumbnails

`FrameStrip.image` decodes one frame per second with `AVAssetImageGenerator.images(for:)`, aspect-fills
each into a cell and returns **one** `CGImage` for the whole strip. One image moves at display rate for
free; forty `Image` views being re-diffed every frame did not. The strip is cached on `EditorModel` for the
video's lifetime and generated at utility priority after the recorder's presentation animation.
`Thumbnail.write` saves a 360-px JPEG at t = 1 s for the project list.
