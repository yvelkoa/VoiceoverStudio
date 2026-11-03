# Persistence

## Layout

```
Documents/Projects/<project-uuid>/
  project.json          manifest (ProjectDocument)
  thumbnail.jpg         poster frame for the list
  video-<uuid>.mov      the picked video, moved here
  take-<uuid>.m4a       recordings
  swapped-<takeid>.mp3  converted voice per take
  effect-<uuid>.mp3     generated sounds
  speech-<uuid>.mp3     Type-mode generated speech
  export-<uuid>.mp4     the last export
```

A project is self-contained: copying the folder is a backup; deleting it removes everything. Files are
referenced **by name**, never by absolute path, because iOS changes the app container path between
launches and updates.

## Why folders + JSON, not SwiftData

- The heavy data is media files either way; the manifest is a few kilobytes.
- The graph is plain values with ids; no relationships worth a database.
- A readable manifest is debuggable with `cat` and testable without a model container.
- Swift 6 strict concurrency with `@Model` classes is still fiddly; `Codable` structs are not.

## Manifest (`ProjectDocument`)

A `nonisolated` `Codable` struct that mirrors `Project` with file names instead of URLs and `uuidString`
keys for the dictionaries (readable JSON; `[UUID: T]` would encode as a flat array). `Voice`, `Character`,
`VoiceSettings`, `TimedWord`, `Caption`, `MixLevels` are `Codable` in the kit/app. Dates are ISO 8601,
output is pretty-printed with sorted keys, writes are atomic.

Stored: title, dates, video file + duration, mode, characters, active character, takes, sequence counter,
transcripts, converted audio + drift, effects, mix, trim, Type-mode script/voice/speech/captions, export file.
Not stored: waveforms (recomputed), frame strip (recomputed), player state.

## Loading

`ProjectStore.loadInBackground` decodes on a detached task and then builds `Project(document:folder:)` on
the main actor. `EditorModel.restore()` rebuilds captions from transcripts, composes a player and kicks off
waveform loads. Missing files degrade gracefully: a clip whose file is gone is skipped by the composer.

## Autosave (`ProjectAutosaver`)

`withObservationTracking { _ = project.document }` registers every persisted property in one read; its
`onChange` schedules a save 600 ms later (debounced) and re-registers. `stop()` cancels the pending save and
writes once more; it is called from `EditorModel`'s `isolated deinit`. There is no Save button anywhere.

## Invalidation rules (where files get deleted)

| Event | Dropped |
|---|---|
| Replace video | takes, converted audio, effects, transcripts, drift, waveforms, Type result, export, trim |
| Delete take | its recording, converted audio, transcript, drift, waveform |
| Change a character's voice or settings | converted audio + drift of that character's takes only |
| Delete character | its takes (as above) |
| Delete effect | its file and waveform |
| Any recompose (new take, effect, trim, mode) | the current export file; `savedToPhotos` resets |
| Export again | the previous export file |

`Project` performs the deletions itself in the same mutation, so the manifest and the folder never
disagree for longer than the autosave delay.

## Store and list

`ProjectStore.refresh()` reads every manifest into `ProjectSummary` (title, date, duration, take count,
exported flag, thumbnail presence). `save` updates the summary in place so the list reorders by last
change without re-reading. `create` makes the folder and writes a first manifest so an empty project is
already a valid one; `delete` removes the folder.
