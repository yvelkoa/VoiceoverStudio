import AVFoundation
import UIKit

/// A JPEG poster frame for the project list.
nonisolated enum Thumbnail {
    @concurrent
    static func write(for video: URL, to destination: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let image = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { return }

        try data.write(to: destination, options: .atomic)
        ProjectStore.excludeFromBackup(destination)
    }
}
