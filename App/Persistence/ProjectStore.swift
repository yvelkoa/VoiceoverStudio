import Foundation
import Observation

/// Projects live in `Documents/Projects/<id>/`, one folder each, with `project.json` and all media inside.
@Observable
final class ProjectStore {
    let root: URL
    private(set) var summaries: [ProjectSummary] = []

    init(root: URL? = nil) {
        self.root = root ?? URL.documentsDirectory.appending(path: "Projects")
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        refresh()
    }

    func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString)
    }

    /// Re-reads every manifest; cheap, they are small.
    func refresh() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        summaries = folders
            .compactMap { folder in
                (try? readDocument(in: folder)).map { ProjectSummary(document: $0, folder: folder) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func create() -> Project {
        let project = Project(folder: folder(for: UUID()), title: "Project \(summaries.count + 1)")
        try? FileManager.default.createDirectory(at: project.folder, withIntermediateDirectories: true)
        try? save(project)
        return project
    }

    func load(_ id: UUID) throws -> Project {
        let folder = folder(for: id)
        return Project(document: try readDocument(in: folder), folder: folder)
    }

    /// Writes the manifest atomically and refreshes the list entry.
    func save(_ project: Project) throws {
        var document = project.document
        document.updatedAt = .now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: project.folder.appending(path: ProjectDocument.fileName), options: .atomic)
        project.updatedAt = document.updatedAt

        let summary = ProjectSummary(document: document, folder: project.folder)
        summaries.removeAll { $0.id == summary.id }
        summaries.insert(summary, at: 0)
    }

    func rename(_ id: UUID, to title: String) {
        guard let project = try? load(id) else { return }
        project.title = title
        try? save(project)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
        summaries.removeAll { $0.id == id }
    }

    private func readDocument(in folder: URL) throws -> ProjectDocument {
        let data = try Data(contentsOf: folder.appending(path: ProjectDocument.fileName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectDocument.self, from: data)
    }
}

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
