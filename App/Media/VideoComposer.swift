import AVFoundation
import UIKit
import VoiceoverKit

/// One piece of audio laid over the video.
nonisolated struct AudioClip: Equatable, Sendable {
    let url: URL
    /// Position on the video's timeline.
    let start: Double
    /// Where to begin inside the file.
    let sourceOffset: Double
    /// Nil plays the file to its end (or the video's end, whichever is first).
    let duration: Double?
    let volume: Float

    init(url: URL, start: Double = 0, sourceOffset: Double = 0, duration: Double? = nil, volume: Float = 1) {
        self.url = url
        self.start = start
        self.sourceOffset = sourceOffset
        self.duration = duration
        self.volume = volume
    }
}

/// Everything needed to both preview (AVPlayer) and export (AVAssetExportSession) the same edit.
nonisolated struct ComposedVideo {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix
    /// Kept as a value type so export can add the caption layers without copying an object graph.
    let videoConfiguration: AVVideoComposition.Configuration

    var videoComposition: AVVideoComposition { AVVideoComposition(configuration: videoConfiguration) }
}

/// Off the main actor: AVFoundation's async APIs take the (non-Sendable) composition across an isolation
/// boundary, which strict concurrency rejects from a main-actor context.
nonisolated enum VideoComposer {
    enum Failure: LocalizedError {
        case noVideoTrack, exportUnavailable

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "This file has no video track."
            case .exportUnavailable: "Export isn't available for this video."
            }
        }
    }

    /// Original audio stays audible under the voiceover, but quietly.
    static let originalAudioVolume: Float = 0.25

    /// Lays `clips` over the picked video. Each clip gets its own track, so clips may overlap freely.
    /// The edit always keeps the video's length; audio that runs past the end is trimmed.
    /// Runs on the cooperative pool; the result is freshly built, so it can be sent back to the caller.
    @concurrent
    static func compose(
        video: URL,
        clips: [AudioClip],
        originalAudioVolume: Float = originalAudioVolume
    ) async throws -> sending ComposedVideo {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }

        let composition = AVMutableComposition()
        let fullRange = CMTimeRange(start: .zero, duration: duration)

        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(fullRange, of: sourceVideo, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        var mixInputs: [AVMutableAudioMixInputParameters] = []
        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try track.insertTimeRange(fullRange, of: sourceAudio, at: .zero)
            mixInputs.append(volume(originalAudioVolume, for: track))
        }

        for clip in clips {
            if let track = try await insert(clip, into: composition, editDuration: duration) {
                mixInputs.append(volume(clip.volume, for: track))
            }
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixInputs

        // Picks up the track's preferredTransform, so portrait phone videos render upright.
        let videoConfiguration = try await AVVideoComposition.Configuration(for: composition)

        return ComposedVideo(composition: composition, audioMix: audioMix, videoConfiguration: videoConfiguration)
    }

    /// Renders the edit with burned-in captions and returns an MP4 in the temporary directory.
    static func export(_ composed: ComposedVideo, captions: [Caption]) async throws -> URL {
        var configuration = composed.videoConfiguration
        let size = configuration.renderSize

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)
        for caption in captions {
            parentLayer.addSublayer(captionLayer(for: caption, renderSize: size))
        }
        configuration.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let preset = AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: composed.composition, presetName: preset) else {
            throw Failure.exportUnavailable
        }
        session.videoComposition = AVVideoComposition(configuration: configuration)
        session.audioMix = composed.audioMix

        let output = URL.temporaryDirectory.appending(path: "voiceover-\(UUID().uuidString).mp4")
        try await session.export(to: output, as: .mp4)
        return output
    }

    // MARK: - Private

    private static func volume(_ volume: Float, for track: AVCompositionTrack) -> AVMutableAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolume(volume, at: .zero)
        return parameters
    }

    /// Adds the clip on its own track. Returns nil when nothing of it falls inside the edit.
    private static func insert(
        _ clip: AudioClip,
        into composition: AVMutableComposition,
        editDuration: CMTime
    ) async throws -> AVMutableCompositionTrack? {
        let asset = AVURLAsset(url: clip.url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else { return nil }

        let start = CMTime(seconds: clip.start, preferredTimescale: 600)
        let offset = CMTime(seconds: clip.sourceOffset, preferredTimescale: 600)
        var available = CMTimeMinimum(try await asset.load(.duration) - offset, editDuration - start)
        if let duration = clip.duration {
            available = CMTimeMinimum(available, CMTime(seconds: duration, preferredTimescale: 600))
        }
        guard available > .zero else { return nil }

        let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try track.insertTimeRange(CMTimeRange(start: offset, duration: available), of: source, at: start)
        return track
    }

    /// One text layer per caption, visible only between its start and end.
    /// Core Animation in an export uses a bottom-left origin, so `y` is measured from the bottom.
    private static func captionLayer(for caption: Caption, renderSize size: CGSize) -> CALayer {
        let fontSize = (min(size.width, size.height) * 0.055).rounded()
        let height = fontSize * 2.8
        let layer = CATextLayer()
        layer.string = caption.text
        layer.font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        layer.fontSize = fontSize
        layer.foregroundColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.8
        layer.shadowRadius = fontSize * 0.15
        layer.shadowOffset = .zero
        layer.alignmentMode = .center
        layer.isWrapped = true
        layer.contentsScale = 2
        // Higher tracks stack above the first one, so simultaneous speakers don't overprint.
        let y = size.height * 0.1 + CGFloat(caption.track) * height
        layer.frame = CGRect(x: size.width * 0.06, y: y, width: size.width * 0.88, height: height)
        layer.opacity = 0

        let visible = CABasicAnimation(keyPath: "opacity")
        visible.fromValue = 1
        visible.toValue = 1
        visible.beginTime = AVCoreAnimationBeginTimeAtZero + caption.start
        visible.duration = max(caption.end - caption.start, 0.05)
        layer.add(visible, forKey: "visible")
        return layer
    }
}
