# Known issues, shortcuts and debt

Honest list for the next review. Each item says why it is still there.

## Platform limits

- **Simulator microphone**: recordings in the simulator came out silent on this machine (default input was
  an aggregate device). Works on device. The live level trace exists partly to make this obvious.
- **Simulator video compositor**: composited frames don't reach `AVPlayerLayer` (`IQ-CA -19230`). The preview
  avoids the compositor; the export still uses it and should be verified on device.
- **On-device transcription languages**: `SpeechTranscriber` covers English and a handful of others; Russian
  and Ukrainian fall back to `SFSpeechRecognizer` (server, ~1 min per request). The take length is well
  under that, but offline it will fail.
- **AVKit scrubber in Preview** shows the full video length even when the export range is trimmed;
  playback is confined with `forwardPlaybackEndTime`.
- **Debug builds** are noticeably slower (no optimisation, concurrency checks). Judge animation smoothness
  in Release.

## Shortcuts taken on purpose

- `EditorModel` is split into `+Recording`, `+Effects` and `+Jobs` extensions with `internal` members to stay
  under SwiftLint's type-length limit. A cleaner split would be separate coordinator objects (recording session,
  swap job, export job) owned by the model.
- `Project` deletes files itself. Keeps manifest and folder in step, but mixes model and filesystem; a
  `ProjectFiles` helper would be the next step.
- `ProjectStore` reads and writes JSON on the main actor except `loadInBackground`. Manifests are tiny; a
  project with hundreds of takes would make this noticeable.
- `ProjectAutosaver` saves 600 ms after the last change and on deinit; a crash inside that window loses
  up to one change. Acceptable for now.
- The debug hook `VOICEOVER_DEBUG_VIDEO` lives in `EditorView+Helpers` behind `#if DEBUG`.
- `Scripts/check.sh` hard-codes the `iPhone 17` simulator destination.
- Transcription errors surface as an alert with Retry; a quieter inline state per take would be better.
- Edits that change the composition are disabled while a job runs (`EditorModel.isBusy`) rather than queued;
  simpler, and a swap takes seconds, not minutes.
- `Waveform` and `FrameStrip` are recomputed per open (utility priority) instead of cached on disk.

## Not done yet

- Localisation: every string is hard-coded English, no String Catalog. The recording-language setting shows
  the audience is multilingual.
- Recording past the end of the video continues until Stop; the composer trims the audio later. Auto-stop at
  the video's end would be the expected behaviour.
- `project.pbxproj` is committed next to `project.yml`. With xcodegen the usual choice is one or the other;
  keeping both means they drift whenever someone forgets `xcodegen generate`.
- No app-level tests. The task slots, the autosaver and the routing of edits through `EditorModel` are
  verified by reading and by the build only; the review in `review-2026-11-03.md` found its bugs there.

- Dragging takes/effects along their lanes; trimming silence at take edges.
- Hearing other characters' takes while recording a reply (needs echo cancellation or headphones).
- Export settings (codec, resolution); today it is H.264 MP4 at source size via `HighestQuality`.
- Filler-word removal via Foundation Models using word timings.
- Streaming TTS.
- Type mode has no sound effects of its own anymore; effects are a project-level lane used by both modes.

## Things that bit us (so they don't again)

1. `analyzeSequence` + `finalizeAndFinish` never ends the results stream; use `finishAfterFile`.
2. `AssetInventory.reserve(locale:)` before requesting a speech model.
3. `Configuration(for: composition)` ignores `preferredTransform` → half-black exports of phone clips.
4. The default audio session obeys the silent switch → "no sound after relaunch". But set the category only
   at launch: `setActive(true)` there silences the user's music before they have done anything.
5. `onDisappear` fires when a child is pushed; use lifetime (`isolated deinit`) for teardown.
6. A missing key permission looks like a rejected key unless `missing_permissions` is handled.
7. Shell: a `;` after a failing build still runs the commit. Use a script with `set -e`.
8. Anything the autosaver tracks must not be written by the save itself (`updatedAt` write-back looped
   every 600 ms).
9. One task slot for everything means a cheap step cancels an expensive one, and a step that re-enters
   `run` cancels itself. Keep compose and jobs in separate slots; call `compose` directly from a job.
10. A retry closure stored on the model must not capture the operation; it captures `self` and the model
    never deinits.
