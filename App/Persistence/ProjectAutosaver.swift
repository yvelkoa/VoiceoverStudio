import Foundation
import Observation

/// Saves a project shortly after anything in it changes.
final class ProjectAutosaver {
    private let project: Project
    private let store: ProjectStore
    private var pending: Task<Void, Never>?
    private var isActive = true
    /// The project as last written (or as loaded). Closing a project that was only looked at must not
    /// rewrite its manifest: the save stamps `updatedAt`, and the list would sort by "last opened".
    private var saved: ProjectDocument

    init(project: Project, store: ProjectStore) {
        self.project = project
        self.store = store
        saved = project.document
        observe()
    }

    func stop() {
        isActive = false
        pending?.cancel()
        save()
    }

    private func save() {
        let document = project.document
        guard document != saved else { return }

        if (try? store.save(project)) != nil { saved = document }
    }

    /// `document` reads every persisted property, so tracking it covers the whole project.
    private func observe() {
        guard isActive else { return }

        withObservationTracking {
            _ = project.document
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.schedule()
                self.observe()
            }
        }
    }

    private func schedule() {
        guard isActive else { return }

        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }

            self.save()
        }
    }
}
