import Photos

/// Adds an exported video to the user's photo library. Asks only for add-only access.
nonisolated enum PhotosSaver {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            switch self {
            case .denied: String(localized: "Photos access is off. Allow “Add Photos Only” for Voiceover Studio in Settings.")
            }
        }
    }

    static func save(_ video: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
        }
    }
}
