import AVFoundation
import UIKit
import VoiceoverKit

/// Everything needed to both preview (AVPlayer) and export (AVAssetExportSession) the same edit.
struct ComposedVideo {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix
    let videoComposition: AVMutableVideoComposition
}

enum VideoComposer {
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

    /// Lays the voice (and optional sound effect) over the picked video.
    /// The edit always keeps the video's length; audio that runs past the end is trimmed.
    static func compose(video: URL, voice: URL, effect: URL?, effectStart: Double) async throws -> ComposedVideo {
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
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(originalAudioVolume, at: .zero)
            mixInputs.append(parameters)
        }

        try await insertAudio(from: voice, into: composition, at: .zero, editDuration: duration)
        if let effect {
            let start = CMTime(seconds: effectStart, preferredTimescale: 600)
            try await insertAudio(from: effect, into: composition, at: start, editDuration: duration)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixInputs

        // Picks up the track's preferredTransform, so portrait phone videos render upright.
        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)

        return ComposedVideo(composition: composition, audioMix: audioMix, videoComposition: videoComposition)
    }

    /// Renders the edit with burned-in captions and returns an MP4 in the temporary directory.
    static func export(_ composed: ComposedVideo, captions: [Caption]) async throws -> URL {
        let videoComposition = composed.videoComposition.mutableCopy() as! AVMutableVideoComposition
        let size = videoComposition.renderSize

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)
        for caption in captions {
            parentLayer.addSublayer(captionLayer(for: caption, renderSize: size))
        }
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let session = AVAssetExportSession(asset: composed.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.exportUnavailable
        }
        session.videoComposition = videoComposition
        session.audioMix = composed.audioMix

        let output = URL.temporaryDirectory.appending(path: "voiceover-\(UUID().uuidString).mp4")
        try await session.export(to: output, as: .mp4)
        return output
    }

    // MARK: - Private

    private static func insertAudio(
        from url: URL,
        into composition: AVMutableComposition,
        at start: CMTime,
        editDuration: CMTime
    ) async throws {
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else { return }
        let available = CMTimeMinimum(try await asset.load(.duration), editDuration - start)
        guard available > .zero else { return }

        let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: available), of: source, at: start)
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
        layer.frame = CGRect(x: size.width * 0.06, y: size.height * 0.1, width: size.width * 0.88, height: height)
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
