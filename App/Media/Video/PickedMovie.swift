import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A video picked from Photos, copied into the app's temporary directory.
nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // The received file is deleted after this closure returns, so keep our own copy.
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = URL.temporaryDirectory.appending(path: "source-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)

            return PickedMovie(url: copy)
        }
    }
}
