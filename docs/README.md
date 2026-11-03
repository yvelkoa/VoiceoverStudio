# Voiceover Studio — engineering docs

Design notes and the reasoning behind them. Each file covers one aspect; read them in this order the first
time.

| File | What it answers |
|---|---|
| [architecture.md](architecture.md) | Layers, folders, who owns what, how data flows through a session |
| [concurrency.md](concurrency.md) | Swift 6 strict concurrency: isolation defaults, `nonisolated`, `@concurrent`, `sending`, actors, deinit |
| [media-pipeline.md](media-pipeline.md) | AVFoundation: composition, clips and tracks, the live mix, preview vs export, rotation, captions |
| [takes-and-timeline.md](takes-and-timeline.md) | Takes, characters, overlap resolution, recording, waveforms, transcription, the scrubber strip |
| [persistence.md](persistence.md) | Project folders, the manifest, autosave, invalidation and file lifecycle |
| [elevenlabs.md](elevenlabs.md) | Endpoints used, permissions, voice settings, errors, credits |
| [known-issues.md](known-issues.md) | Limits, shortcuts and debt, with the reason each one is still there |
| [review-2026-11-03.md](review-2026-11-03.md) | Full code review (architecture, concurrency, SwiftUI, media, persistence) and what was done about each finding |

Conventions used throughout:

- **"Kit"** is `Packages/VoiceoverKit`, the UI-free Swift package. **"App"** is the SwiftUI target.
- Times are seconds as `Double` on the timeline; `CMTime` appears only at AVFoundation boundaries.
- A **take** is one microphone pass; a **segment** is the audible slice of a take after overlap resolution;
  a **clip** is what the composer receives (a file, a start, an offset, a duration, a kind).
