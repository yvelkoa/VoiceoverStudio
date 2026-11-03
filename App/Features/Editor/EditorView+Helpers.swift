import PhotosUI
import SwiftUI
import VoiceoverKit

// Loading the picked video, the debug video hook and the failure alert.
extension EditorView {

    func loadVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingVideo = true
        Task {
            defer { isLoadingVideo = false }
            do {
                if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                    await model.setVideo(movie.url)
                }
            } catch {
                model.failure = .init(message: "Couldn't load this video.", recovery: .none)
            }
        }
    }

    func failureAlert(_ failure: EditorModel.Failure) -> Alert {
        switch failure.recovery {
        case .openSettings:
            Alert(
                title: Text("Something went wrong"),
                message: Text(failure.message),
                primaryButton: .default(Text("Open Settings")) { showsSettings = true },
                secondaryButton: .cancel()
            )
        case .retry:
            Alert(
                title: Text("Something went wrong"),
                message: Text(failure.message),
                primaryButton: .default(Text("Retry")) { failure.retry?() },
                secondaryButton: .cancel()
            )
        case .editInput, .none:
            Alert(title: Text("Something went wrong"), message: Text(failure.message))
        }
    }
}
