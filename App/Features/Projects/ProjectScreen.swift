import SwiftUI

/// Loads a project from disk and hosts its editor for as long as it is on screen.
struct ProjectScreen: View {
    let projectID: UUID
    @Environment(AppModel.self) private var app
    @State private var model: EditorModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                EditorView(model: model)
            } else if failed {
                ContentUnavailableView("Couldn't open this project", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .task(id: projectID) {
            guard model == nil else { return }
            // Let the push animation run on an empty screen; the player and waveforms start right after.
            try? await Task.sleep(for: .milliseconds(300))
            do {
                let project = try await app.store.loadInBackground(projectID)
                model = app.editor(for: project)
            } catch {
                failed = true
            }
        }
    }
}
