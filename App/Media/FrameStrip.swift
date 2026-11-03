import AVFoundation
import CoreGraphics

/// Thumbnails along a video, for the scrubber strip.
nonisolated enum FrameStrip {
    struct Frame: Identifiable, Sendable {
        let id: Int
        let time: Double
        let image: CGImage
    }

    /// One frame per `interval` seconds, each at most `height` points tall (times the screen scale).
    @concurrent
    static func frames(
        for video: URL,
        duration: Double,
        interval: Double,
        height: CGFloat,
        scale: CGFloat
    ) async throws -> [Frame] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 0, height: height * scale)
        let tolerance = CMTime(seconds: interval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let count = max(1, Int((duration / interval).rounded(.up)))
        let times = (0..<count).map { index in
            CMTime(seconds: min(Double(index) * interval + interval / 2, duration), preferredTimescale: 600)
        }

        var frames: [Frame] = []
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            // A frame that fails to decode leaves a gap rather than failing the whole strip.
            guard let image = try? result.image else { continue }
            frames.append(Frame(id: frames.count, time: result.requestedTime.seconds, image: image))
        }
        return frames
    }
}
