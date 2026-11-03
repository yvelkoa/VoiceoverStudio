import Foundation
import Observation

/// Saves a project shortly after anything in it changes.
final class ProjectAutosaver {
    private let project: Project
    private let store: ProjectStore
    private var pending: Task<Void, Never>?
    private var isActive = true

    init(project: Project, store: ProjectStore) {
        self.project = project
        self.store = store
        observe()
    }

    func stop() {
        isActive = false
        pending?.cancel()
        try? store.save(project)
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
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            try? self.store.save(self.project)
        }
    }
}
