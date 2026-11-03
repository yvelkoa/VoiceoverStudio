# Swift concurrency decisions

The whole project builds with `SWIFT_STRICT_CONCURRENCY=complete`, Swift 6 language mode, and two
"approachable concurrency" settings in `project.yml`:

- `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` — every type in the app is main-actor isolated unless it says
  otherwise. UI, models and orchestration are all main-actor and need no annotations.
- `SWIFT_APPROACHABLE_CONCURRENCY: YES` — among other things, `nonisolated async` functions run on the
  caller's actor (SE-0461) unless marked `@concurrent`.

So the question for each type is only: *does it need to run off the main actor?* Three answers exist.

## 1. Main actor (the default): state and orchestration

`Project`, `EditorModel`, `TakeRecorder`, `ProjectStore`, `ProjectAutosaver`, every view. They mutate
observable state and talk to UIKit/AVKit objects that are main-actor bound. Nothing to annotate.

## 2. `nonisolated` types: pure work and value types

Declared with `nonisolated` on the type:

- **Value types that cross isolation**: `AudioClip`, `AudioKind`, `MixLevels`, `ComposedVideo`,
  `ProjectDocument`, `ProjectSummary`, `EditingMode`, `Waveform`, `APIKeyStore`, `PickedMovie`. Without
  `nonisolated` a struct is main-actor isolated and its `Codable` conformance can't be used from a
  background decode (`ProjectStore.loadInBackground` hit exactly that error). The same applies to each
  `extension` of such a type: the default isolation is per declaration, so an extension holding
  `init(from:)` must say `nonisolated` again or the conformance "crosses into main actor-isolated code".
- **Workers with no state**: `VideoComposer`, `VoiceSwapper`, `Transcriber`, `FrameStrip`, `Thumbnail`,
  `PhotosSaver`. They are `enum`s with static functions, so there is no instance to protect.

## 3. `@concurrent`: work that must leave the main actor

Under approachable concurrency a `nonisolated async` function *inherits* the caller's actor. That is right
for small helpers but wrong for `VideoComposer.compose`, `FrameStrip.image`, `Waveform.load`,
`Transcriber.words`, `Thumbnail.write`: they decode media or call AVFoundation's async loaders and must not
run on the main actor. They are marked `@concurrent`, which pins them to the cooperative pool.

The first bug of the project was here. `AVMutableVideoComposition.videoComposition(withPropertiesOf:)` is
an Objective-C async method, i.e. it always hops to a background executor. Calling it from a main-actor
`compose` *sent* the non-Sendable `AVMutableComposition` across an isolation boundary and the compiler
rejected it ("sending value of non-Sendable type … risks causing data races"). Once `compose` is
`@concurrent`, the composition never leaves the nonisolated context and the call is fine.

### `sending` results

`compose` builds `AVMutableComposition`, `AVVideoComposition.Configuration` and the track map and returns
them inside `ComposedVideo`, a non-Sendable struct. Returning it to the main actor is allowed because the
function is declared `-> sending ComposedVideo`: region-based isolation checking proves the value was
created inside the function and nothing else holds it. No `@unchecked Sendable` wrapper needed.

### Things that must stay on the main actor even in media code

- `AVPlayerItem` is main-actor bound in the iOS 26 SDK. An attempt to construct it inside `compose` failed
  to compile; `EditorModel.compose` creates it on the main actor instead. It is cheap: the loading it
  triggers is asynchronous.
- `AVPlayer`, `AVPlayerLayer`, `AVAudioRecorder` live in main-actor types.

## Actors

`ElevenLabsClient` is an `actor` because it owns the voice-list cache that several screens read. Its
`HTTPTransport` is a `Sendable` protocol so tests can inject a stub; the test stub uses a lock and is
`@unchecked Sendable`, which is the honest way to make a mutable recorder of requests thread-safe.

## Closures that cross isolation

- `VoiceSwapper.convert(_:client:into:onOutcome:)` takes `@MainActor @Sendable (Outcome) -> Void`. Results
  of parallel network calls are delivered one by one on the main actor so `Project` can be updated as each
  take lands, instead of after all of them.
- `EditorModel.run` captures `[client, project]` explicitly where the operation runs off-actor to avoid
  capturing `self` into a `@Sendable` context by accident.
- `Failure.retry` must not capture the operation closure: operations capture `self` strongly, the failure
  lives on `self`, and the resulting cycle would defeat `isolated deinit` below. Retries are
  `{ [weak self] in self?.method(values) }`.

## Observation

- `@Observable` classes everywhere; no Combine.
- `ProjectAutosaver` uses `withObservationTracking` recursively: it reads `Project.document` (a computed
  snapshot that touches every persisted property), gets a one-shot `onChange`, hops to the main actor,
  schedules a debounced save and re-registers. This is how "save after any change" works without listing
  properties.
- `TimelineStrip` reads `player.currentTime()` inside `TimelineView(.animation)` so the strip is positioned
  per display frame from the player's clock rather than from a 10 Hz time observer.

## Lifetimes and `isolated deinit`

`EditorModel` used to flush and stop in `onDisappear`. That also fires when a child screen (voice picker)
is pushed, which cancelled running exports and stopped autosave. Now `EditorModel` has an
`isolated deinit` (SE-0371, Swift 6.2) that runs on the main actor when `ProjectScreen` is popped and its
`@State` releases the model: cancel tasks, pause the player, final save. Nothing else holds the model, so
the lifetime is exactly the screen's. This only works while nothing on the model points back at it; see the
rule for `Failure.retry` above.

### Two task slots

`EditorModel` keeps `composeTask` and `jobTask` apart. The first version had one `work` task that each `run`
cancelled, which made a cheap `recompose()` after a deleted take cancel a running swap (already billed), and
made `addEffect` cancel *itself* when it called `recompose()` at its end, so the effect's waveform load that
followed saw a cancelled task and quietly returned nothing.

## Task priorities and deferral

- Waveforms and the frame strip run as `Task(priority: .utility)`; they are nice-to-have decorations. The
  waveforms of a loaded project decode one after another in a single tracked task (`waveformTask`), so the
  editor's deinit can cancel them and the decoder doesn't compete with the player that just started.
- Disk writes of generated audio (`EditorModel.write`) are `@concurrent`; a few megabytes on the main actor
  was a visible hitch on the button that triggered them.
- `ProjectScreen` waits 300 ms before loading so the push animation gets the main thread; the manifest is
  decoded in `Task.detached(priority: .userInitiated)`.
- `RecordingView` waits 350 ms before asking for the frame strip for the same reason.

## Rules of thumb used in this codebase

1. Default to main actor; annotate only what provably needs to leave it.
2. Prefer `nonisolated` value types over `@unchecked Sendable` classes.
3. If a function decodes media, it is `@concurrent` and returns `sending` or `Sendable` values.
4. Never pass a main-actor object into a `@concurrent` function; pass URLs, values and ids.
5. When the compiler complains about sending, move the work, not the annotation.
