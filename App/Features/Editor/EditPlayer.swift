import AVFoundation
import Observation
import VoiceoverKit

/// The one `AVPlayer` of an open project and the edit it is playing.
///
/// Rebuilding keeps the playhead and the playing state; the mix is applied to the item without a rebuild.
/// It knows nothing about takes or modes: the owner hands it the clips.
@Observable
final class EditPlayer {
    private(set) var player: AVPlayer?
    private(set) var composed: ComposedVideo?
    private let composer: @Sendable (URL, [AudioClip]) async throws -> sending ComposedVideo

    init(compose: @escaping @Sendable (URL, [AudioClip]) async throws -> sending ComposedVideo) {
        composer = compose
    }

    /// Builds the edit from `clips` over `video` and puts it on the player, resuming where it was.
    func compose(video: URL, clips: [AudioClip], mix: MixLevels) async throws {
        let wasPlaying = player?.rate ?? 0 > 0
        let resumeAt = player?.currentTime()

        let composed = try await composer(video, clips)
        try Task.checkCancellation()

        // No video composition for the preview: AVPlayer applies the track's preferredTransform itself and
        // captions are a SwiftUI overlay. The compositor is only needed for the export, and in the simulator
        // its frames can't be displayed by AVPlayerLayer at all (IQ-CA error -19230, black video).
        // AVPlayerItem is main-actor bound in iOS 26; creating it is cheap, loading happens asynchronously.
        let item = AVPlayerItem(asset: composed.asset)
        item.audioMix = composed.audioMix(previewLevels(mix, for: composed))
        self.composed = composed

        if let player {
            player.replaceCurrentItem(with: item)
            // Not awaited: the seek completes only once the item is ready, and an item that never gets there
            // (an empty edit on the iOS 26 simulator) would hold the job that composed it forever.
            // AVPlayer applies the seek before the play below.
            if let resumeAt { player.seek(to: resumeAt) { _ in } }
            if wasPlaying { player.play() }
        } else {
            player = AVPlayer(playerItem: item)
        }
    }

    /// Pushes new levels onto the playing item without rebuilding anything.
    func applyMix(_ mix: MixLevels) {
        guard let composed else { return }

        player?.currentItem?.audioMix = composed.audioMix(previewLevels(mix, for: composed))
    }

    func pause() {
        player?.pause()
    }

    /// Drops the player and the edit, e.g. before a new video.
    func reset() {
        player?.pause()
        player = nil
        composed = nil
    }

    /// The project's mix, except that with nothing to duck under the original plays at full volume, so a
    /// freshly picked video sounds normal. Preview only; the export takes the mix as set.
    private func previewLevels(_ mix: MixLevels, for composed: ComposedVideo) -> MixLevels {
        var levels = mix
        if composed.trackKinds.values.allSatisfy({ $0 == .original }) { levels.original = 1 }

        return levels
    }
}
