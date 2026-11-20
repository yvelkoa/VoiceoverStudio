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

    /// Re-reads every manifest; cheap, they are small. A manifest that exists but does not decode still gets
    /// a row, so a format mistake shows up as "unreadable" rather than as a vanished project.
    func refresh() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        summaries = folders
            .compactMap { folder -> ProjectSummary? in
                guard let id = UUID(uuidString: folder.lastPathComponent) else { return nil }

                if let document = try? readDocument(in: folder) { return ProjectSummary(document: document, folder: folder) }
                let manifest = folder.appending(path: ProjectDocument.fileName)
                guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }

                return ProjectSummary(unreadableFolder: folder, id: id)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func create() -> Project {
        let project = Project(folder: folder(for: UUID()), title: String(localized: "Project \(summaries.count + 1)"))
        try? FileManager.default.createDirectory(at: project.folder, withIntermediateDirectories: true)
        try? save(project)

        return project
    }

    func load(_ id: UUID) throws -> Project {
        let folder = folder(for: id)
        return Project(document: try readDocument(in: folder), folder: folder)
    }

    /// Reads and decodes the manifest off the main actor, then builds the project.
    func loadInBackground(_ id: UUID) async throws -> Project {
        let folder = folder(for: id)
        let document = try await Task.detached(priority: .userInitiated) { try Self.decodeDocument(in: folder) }.value

        return Project(document: document, folder: folder)
    }

    /// Writes the manifest atomically and refreshes the list entry.
    /// Deliberately does not write anything back into `project`: the autosaver tracks every persisted
    /// property, so a write-back here (e.g. `updatedAt`) would schedule the next save and loop forever.
    func save(_ project: Project) throws {
        var document = project.document
        document.updatedAt = .now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: project.folder.appending(path: ProjectDocument.fileName), options: .atomic)

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
        try Self.decodeDocument(in: folder)
    }

    /// Exports and thumbnails can be regenerated from the rest of the project; iCloud need not carry them.
    nonisolated static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    nonisolated private static func decodeDocument(in folder: URL) throws -> ProjectDocument {
        let data = try Data(contentsOf: folder.appending(path: ProjectDocument.fileName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(ProjectDocument.self, from: data)
    }
}
