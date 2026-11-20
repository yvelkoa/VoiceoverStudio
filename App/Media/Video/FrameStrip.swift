import AVFoundation
import CoreGraphics

/// A single wide image of thumbnails along a video, for the scrubber strip.
/// One image instead of dozens of views keeps the strip cheap to move every display frame.
nonisolated enum FrameStrip {
    /// One frame per `interval` seconds, each `cellSize` points (times the screen scale), aspect-filled.
    @concurrent
    static func image(
        for video: URL,
        duration: Double,
        interval: Double,
        cellSize: CGSize,
        scale: CGFloat
    ) async throws -> CGImage? {
        let frameWidth = cellSize.width
        let height = cellSize.height
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

        let cellWidth = frameWidth * scale
        let cellHeight = height * scale
        guard let context = CGContext(
            data: nil,
            width: Int(cellWidth * CGFloat(count)),
            height: Int(cellHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))

        var index = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            defer { index += 1 }
            // A frame that fails to decode leaves a dark cell rather than failing the whole strip.
            guard let frame = try? result.image else { continue }

            let cell = CGRect(x: cellWidth * CGFloat(index), y: 0, width: cellWidth, height: cellHeight)
            context.saveGState()
            context.clip(to: cell)
            context.draw(frame, in: aspectFill(CGSize(width: frame.width, height: frame.height), into: cell))
            context.restoreGState()
        }

        return context.makeImage()
    }

    private static func aspectFill(_ size: CGSize, into rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)

        return CGRect(
            x: rect.midX - scaled.width / 2,
            y: rect.midY - scaled.height / 2,
            width: scaled.width,
            height: scaled.height
        )
    }
}
