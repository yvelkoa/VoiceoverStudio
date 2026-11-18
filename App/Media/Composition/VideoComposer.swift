import AVFoundation
import UIKit
import VoiceoverKit

/// Off the main actor: AVFoundation's async APIs take the (non-Sendable) composition across an isolation
/// boundary, which strict concurrency rejects from a main-actor context.
nonisolated enum VideoComposer {
    enum Failure: LocalizedError {
        case noVideoTrack, exportUnavailable

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: String(localized: "This file has no video track.")
            case .exportUnavailable: String(localized: "Export isn't available for this video.")
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

        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.noVideoTrack }
        try videoTrack.insertTimeRange(fullRange, of: sourceVideo, at: .zero)
        let (naturalSize, transform, frameRate) = try await sourceVideo.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        // The preview has no video composition and relies on this to show phone footage upright.
        videoTrack.preferredTransform = transform

        var trackKinds: [CMPersistentTrackID: AudioKind] = [:]
        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
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

    /// Renders the edit with burned-in captions at the given mix into `output` (an MP4 in the project folder).
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
        guard let session = AVAssetExportSession(asset: composed.asset, presetName: preset) else {
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

        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
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
        // CATextLayer documents CTFont, CGFont or a name; a UIFont works only through its name and can lose the
        // weight of the system font. The descriptor keeps it.
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        layer.font = CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, fontSize, nil)
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
