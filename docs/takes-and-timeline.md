# Takes, characters and the timeline

## Model

```
Character { id, name, voice: Voice?, settings: VoiceSettings, colorIndex }
Take      { id, characterID, start, duration, recording: URL, sequence }
AudioSegment { takeID, characterID, start, sourceOffset, duration }     // output of TakeResolver
SoundEffect  { id, prompt, start, duration, audio: URL }
```

`sequence` is the recording order and the only thing that decides precedence. `start` is where the user
pressed Record on the timeline; `duration` is what the recorder measured at Stop.

## Overlap resolution (`TakeResolver`, kit, tested)

Rule: **within one character the newest take wins where takes overlap; characters never cut each other.**

Per character, takes are sorted by `sequence`; each take's range has every *later* take's range subtracted,
which yields zero, one or two slices (a punch-in in the middle splits the older take in two). Slices shorter
than 50 ms are dropped. Each surviving slice is an `AudioSegment` with `sourceOffset = slice.start -
take.start`, so the composer plays exactly the right part of the file. The result is sorted by start.

Why not edit the files? Because nothing is destructive: deleting the newer take brings the older one back
whole, and the same resolution feeds captions and the timeline lanes.

## Recording (`TakeRecorder`)

- AAC, 44.1 kHz, mono, high quality, into `take-<uuid>.m4a` inside the project folder.
- Permission via `AVAudioApplication.requestRecordPermission()`.
- `isMeteringEnabled`; a `Task` samples `peakPower` every 20 ms (the `Waveform.bucket`) and fills
  `liveLevels` **up to the recorder's own clock** (`currentTime / bucket`). Filling by clock rather than by
  tick count is what keeps the live trace aligned with the playhead when the timer runs late.
- Minimum take length is `TakeResolver.minimumDuration`; shorter stops are discarded and their file deleted.
- `start(in:)` refuses while a recorder exists, and `EditorModel.isStartingRecording` covers the gap while
  the microphone permission prompt is up, so a double tap on Record cannot start two recorders (the first
  would have kept metering into `liveLevels` with no one to stop it).

## Waveforms (`Waveform`)

The recording is read as 16 kHz mono 16-bit PCM through `AVAssetReader`; the peak of each 20 ms bucket is
kept as linear amplitude × 1.6 gain, clipped to 1. The live meter converts dBFS to the same linear scale
(`Waveform.level(fromDecibels:)`). Earlier the live meter was dB-linear and the stored waveform was
normalised to its own maximum; the two looked nothing alike. Waveforms are not persisted; they are
recomputed at utility priority when a project opens.

`levels(from:duration:count:)` resamples a slice for drawing, so a split take draws the right part.

## Transcription (`Transcriber`)

Two engines behind one function, chosen per locale:

| Locale supported by `SpeechTranscriber` | Engine | Where it runs |
|---|---|---|
| en, de, fr, es, it, pt, ja, ko, zh (iOS 26 list) | `SpeechAnalyzer` + `SpeechTranscriber` | on device |
| everything else, incl. **ru, uk** | `SFSpeechRecognizer` | Apple servers, ~1 min per request |

Details that cost time to learn:

- The app must `AssetInventory.reserve(locale:)` before `assetInstallationRequest`; otherwise the request
  fails with "not subscribed to transcription.en".
- `analyzer.analyzeSequence(from:)` + `finalizeAndFinish(through:)` leaves `transcriber.results` open
  forever; `start(inputAudioFile:finishAfterFile: true)` ends the stream. Verified with synthesized speech.
- Word times come from the `audioTimeRange` run attribute of the result's `AttributedString`.
- `SFSpeechRecognizer` results are converted to `[TimedWord]` *inside* the callback because `SFTranscription`
  is not `Sendable`; a lock-guarded `ResumeOnce` guards the continuation against a second callback.

The recording language is a setting (`RecordingLanguage`, UserDefaults), defaulting to the device locale.

## Captions from takes (`CaptionAssembler`, kit, tested)

For every segment, words of its take whose start lies inside the slice are shifted by
`segment.start - sourceOffset` onto the timeline. Words are grouped per character and sent through
`CaptionBuilder.captions`, which breaks lines at `. ! ?`, at 32 characters or at 3 s. Each character gets a
`track` equal to its index, so two people talking at once render on two lines. Ids are unique across
characters.

## Voice swap (`VoiceSwapper`)

Each take is sent separately (cheaper than one flattened file: no silence billed, retries per take). At most
three requests are in flight. The converted MP3 replaces the recording in `voiceClips()`; the length
difference is stored as `conversionDrift` and flagged in the UI above 150 ms, since captions are timed from
the recording. Changing a character's voice or settings invalidates only that character's conversions.

## The scrubber (`TimelineStrip`)

A Photos-style strip: content slides under a fixed playhead. Three ways it moves, in priority order:

1. **Scrubbing**: `DragGesture(minimumDistance: 4)` maps finger translation 1:1 to time
   (`pointsPerSecond = 56`). On release, `coast(velocity:)` continues at the gesture's velocity with
   UIScrollView's deceleration curve (0.998 per ms, stepped at 120 Hz) until it stops, hits an end, or a new
   touch cancels it. `isScrubbing` stays true while coasting.
2. **Playing**: `TimelineView(.animation)` re-evaluates every display frame and reads
   `player.currentTime()`; the strip is positioned by `.offset`, not by scrolling.
3. **Idle**: positioned at `currentTime` passed in by the owner (after seeks, stops, first appearance).

A tap seeks to the tapped moment. Seeks issued while scrubbing are **coalesced** in `RecordingView`: one in
flight, only the newest pending time is honoured, tolerance 1/30 s. Without that a 60 fps clip lagged
behind the finger.

Why not a `ScrollView`: the first version used `ScrollPosition` with one long linear animation during
playback. It was smooth but the animation outlived a pause and the strip kept moving after a take stopped;
`TimelineView` has no such state.

Lanes: one per character in declaration order with the resolved segments (tinted block + waveform), plus a
live segment in full colour while recording; one Effects lane with prompt text; the trim range is shown by
dimming the strip outside it.
