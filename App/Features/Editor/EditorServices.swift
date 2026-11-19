import AVFoundation
import Foundation
import VoiceoverKit

/// The media and system work the editor depends on, as plain functions.
///
/// `.live` calls AVFoundation, Photos and the speech recogniser. Tests and previews replace only the parts
/// they need, so the editor's jobs (export, music, transcription, rebuilding the edit) run in a unit test
/// without media files, a photo library or a microphone. The network is replaced one level lower, through
/// the client's `HTTPTransport`.
///
/// Not covered: the microphone (`RecordingSession`) and the scrubber's frame strip. Both need real hardware
/// or real video to mean anything and are checked by hand.
nonisolated struct EditorServices: Sendable {
    /// Lays the clips over the video. See `VideoComposer.compose`.
    var compose: @Sendable (_ video: URL, _ clips: [AudioClip]) async throws -> sending ComposedVideo
    /// Renders the edit into `output` and returns it. See `VideoComposer.export`. Runs on the caller's actor:
    /// the composed edit belongs to the player and must not be sent anywhere else.
    var export: nonisolated(nonsending) @Sendable (
        _ composed: ComposedVideo,
        _ captions: [Caption],
        _ levels: MixLevels,
        _ range: ClosedRange<Double>?,
        _ output: URL
    ) async throws -> URL
    var saveToPhotos: @Sendable (_ video: URL) async throws -> Void
    var transcribe: @Sendable (_ recording: URL, _ locale: Locale) async throws -> [TimedWord]
    /// The language takes are spoken in; read when a take is transcribed, so a change in Settings applies.
    var recordingLocale: @Sendable () -> Locale
    var waveform: @Sendable (_ audio: URL) async throws -> Waveform
    /// Length of an audio or video file in seconds.
    var duration: @Sendable (_ media: URL) async throws -> Double
    var writeThumbnail: @Sendable (_ video: URL, _ destination: URL) async throws -> Void
    /// Sound effects and a music prompt suggested from the captions, streamed as the plan grows. See
    /// `SoundDirector.plan`. `locale` is the language of the words when known.
    var planSounds: @Sendable (
        _ captions: [Caption], _ videoDuration: Double, _ locale: Locale?
    ) -> AsyncThrowingStream<SoundPlan, any Error>
    /// Loads the on-device model before the user asks, so the first suggestion doesn't wait for it.
    var prewarmSoundDirector: @Sendable () -> Void
}

nonisolated extension EditorServices {
    static let live = EditorServices(
        compose: { video, clips in try await VideoComposer.compose(video: video, clips: clips) },
        export: { composed, captions, levels, range, output in
            try await VideoComposer.export(composed, captions: captions, levels: levels, range: range, to: output)
        },
        saveToPhotos: { video in try await PhotosSaver.save(video) },
        transcribe: { recording, locale in try await Transcriber.words(in: recording, locale: locale) },
        recordingLocale: { RecordingLanguage.locale },
        waveform: { audio in try await Waveform.load(audio) },
        duration: { media in try await AVURLAsset(url: media).load(.duration).seconds },
        writeThumbnail: { video, destination in try await Thumbnail.write(for: video, to: destination) },
        planSounds: { captions, duration, locale in
            SoundDirector.plan(for: captions, videoDuration: duration, locale: locale)
        },
        // Off the main actor: loading the model can hold the calling thread for seconds, and taps on the
        // editor that just appeared were lost while it did.
        prewarmSoundDirector: { Task.detached(priority: .utility) { SoundDirector.prewarm() } }
    )
}
