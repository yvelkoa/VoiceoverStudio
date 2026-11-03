import AVFoundation
import UIKit
import VoiceoverKit

/// What an audio track carries, so the mix can set one level per kind.
nonisolated enum AudioKind: Hashable, Sendable {
    case original, voice, effect
}

/// Levels per kind, 0...1.
nonisolated struct MixLevels: Equatable, Codable, Sendable {
    var original: Float = 0.25
    var voice: Float = 1
    var effect: Float = 0.8

    func level(for kind: AudioKind) -> Float {
        switch kind {
        case .original: original
        case .voice: voice
        case .effect: effect
        }
    }
}

/// One piece of audio laid over the video.
nonisolated struct AudioClip: Equatable, Sendable {
    let url: URL
    let kind: AudioKind
    /// Position on the video's timeline.
    let start: Double
    /// Where to begin inside the file.
    let sourceOffset: Double
    /// Nil plays the file to its end (or the video's end, whichever is first).
    let duration: Double?

    init(url: URL, kind: AudioKind, start: Double = 0, sourceOffset: Double = 0, duration: Double? = nil) {
        self.url = url
        self.kind = kind
        self.start = start
        self.sourceOffset = sourceOffset
        self.duration = duration
    }
}

/// Everything needed to both preview (AVPlayer) and export (AVAssetExportSession) the same edit.
nonisolated struct ComposedVideo {
    let composition: AVMutableComposition
    /// Which kind each audio track carries; the mix is rebuilt from this whenever a level changes.
    let trackKinds: [CMPersistentTrackID: AudioKind]
    /// Kept as a value type so export can add the caption layers without copying an object graph.
    let videoConfiguration: AVVideoComposition.Configuration

    var videoComposition: AVVideoComposition { AVVideoComposition(configuration: videoConfiguration) }

    /// A fresh mix at the given levels. Cheap: no media is touched, so it can follow a slider live.
    func audioMix(_ levels: MixLevels) -> AVMutableAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = composition.tracks(withMediaType: .audio).compactMap { track in
            guard let kind = trackKinds[track.trackID] else { return nil }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(levels.level(for: kind), at: .zero)
            return parameters
        }
        return mix
    }
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

    /// Lays `clips` over the picked video. Each clip gets its own track, so clips may overlap freely.
    /// The edit always keeps the video's length; audio that runs past the end is trimmed.
    /// Runs on the cooperative pool; the result is freshly built, so it can be sent back to the caller.
    @concurrent
    static func compose(video: URL, clips: [AudioClip]) async throws -> sending ComposedVideo {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }

        let composition = AVMutableComposition()
        let fullRange = CMTimeRange(start: .zero, duration: duration)

        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(fullRange, of: sourceVideo, at: .zero)
        let (naturalSize, transform, frameRate) = try await sourceVideo.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        // The preview has no video composition and relies on this to show phone footage upright.
        videoTrack.preferredTransform = transform

        var trackKinds: [CMPersistentTrackID: AudioKind] = [:]
        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try track.insertTimeRange(fullRange, of: sourceAudio, at: .zero)
            trackKinds[track.trackID] = .original
        }

        for clip in clips {
            if let track = try await insert(clip, into: composition, editDuration: duration) {
                trackKinds[track.trackID] = clip.kind
            }
        }

        let videoConfiguration = videoConfiguration(
            for: videoTrack, naturalSize: naturalSize, transform: transform, frameRate: frameRate, range: fullRange
        )

        return ComposedVideo(composition: composition, trackKinds: trackKinds, videoConfiguration: videoConfiguration)
    }

    /// Renders the edit with burned-in captions at the given mix and returns an MP4 in the temporary directory.
    /// `range` keeps only that part of the timeline; caption times stay in composition time, so nothing shifts.
    static func export(
        _ composed: ComposedVideo,
        captions: [Caption],
        levels: MixLevels,
        range: ClosedRange<Double>? = nil,
        to output: URL
    ) async throws -> URL {
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
        session.audioMix = composed.audioMix(levels)
        if let range {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
            session.timeRange = CMTimeRange(start: start, end: end)
        }

        try await session.export(to: output, as: .mp4)
        return output
    }

    // MARK: - Private

    /// The export's video composition, built by hand. `Configuration(for:)` on a composition ignores the
    /// track's preferredTransform: a portrait phone clip (1920×1080 rotated 90°) came out as a landscape frame
    /// with the picture in one half and black in the other. Here the render size is the transformed natural
    /// size and the transform is re-anchored so the picture starts at the origin.
    private static func videoConfiguration(
        for track: AVMutableCompositionTrack,
        naturalSize: CGSize,
        transform: CGAffineTransform,
        frameRate: Float,
        range: CMTimeRange
    ) -> AVVideoComposition.Configuration {
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let renderSize = CGSize(width: abs(bounds.width).rounded(), height: abs(bounds.height).rounded())
        let anchored = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))

        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        layer.setTransform(anchored, at: .zero)
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: range
        ))
        return AVVideoComposition.Configuration(
            frameDuration: CMTime(value: 1, timescale: max(Int32(frameRate.rounded()), 24)),
            instructions: [instruction],
            renderSize: renderSize
        )
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
