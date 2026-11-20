import PhotosUI
import SwiftUI
import VoiceoverKit

// Loading the picked video, the debug video hook, the failure alert and where a picked voice goes.
extension EditorView {

    func loadVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }

        isLoadingVideo = true
        Task {
            defer { isLoadingVideo = false }
            do {
                if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                    // Let the picker finish its dismiss animation before the form re-lays out around the video.
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation { isLoadingVideo = false }
                    await model.setVideo(movie.url)
                }

                // Cleared so that picking the same item again counts as a change.
                pickedItem = nil
            } catch {
                model.failure = .init(message: String(localized: "Couldn't load this video."), recovery: .none)
            }
        }
    }

    /// The alert's buttons follow the failure's recovery; the message is the failure's own text.
    @ViewBuilder
    func failureActions(_ failure: EditorModel.Failure) -> some View {
        switch failure.recovery {
        case .openSettings:
            Button("Open Settings") { showsSettings = true }
            Button("Cancel", role: .cancel) {}
        case .retry:
            Button("Retry") { failure.retry?() }
            Button("Cancel", role: .cancel) {}
        case .editInput, .none:
            Button("OK", role: .cancel) {}
        }
    }

    /// Where a picked voice goes: the Type-mode voice, or a character (through the model, so its stale
    /// conversions are dropped and the edit rebuilt).
    func voiceBinding(_ target: VoiceTarget) -> Binding<Voice?> {
        switch target {
        case .script:
            return $model.voice
        case .character(let id):
            return Binding(
                get: { model.project.character(id)?.voice },
                set: { voice in
                    guard var updated = model.project.character(id) else { return }

                    updated.voice = voice
                    model.update(updated)
                }
            )
        }
    }
}
