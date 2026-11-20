import Foundation
import Testing
@testable import VoiceoverStudio

/// Saves 600 ms after the last change. Once it looped, saving every 600 ms forever, because the save
/// itself counted as a change; `savingIsNotAChange` guards against that coming back.
struct ProjectAutosaverTests {
    private let folder = TemporaryFolder()

    private func manifest(of project: Project) throws -> ProjectDocument {
        let data = try Data(contentsOf: project.folder.appending(path: ProjectDocument.fileName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(ProjectDocument.self, from: data)
    }

    @Test func aChangeIsSavedShortlyAfter() async throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let project = store.create()
        let saver = ProjectAutosaver(project: project, store: store)
        defer { saver.stop() }

        project.title = "Autosaved"

        #expect(try manifest(of: project).title != "Autosaved")
        #expect(await eventually { (try? manifest(of: project).title) == "Autosaved" })
    }

    @Test func savingIsNotAChange() async throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let project = store.create()
        let saver = ProjectAutosaver(project: project, store: store)
        defer { saver.stop() }

        project.script = "Once"
        #expect(await eventually { (try? manifest(of: project).script) == "Once" })
        let firstSave = try manifest(of: project).updatedAt

        try await Task.sleep(for: .milliseconds(1500))

        #expect(try manifest(of: project).updatedAt == firstSave)
    }

    @Test func closingAnUntouchedProjectDoesNotRewriteIt() async throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let project = store.create()
        let created = try manifest(of: project).updatedAt
        let saver = ProjectAutosaver(project: project, store: store)

        // The manifest's dates have one-second resolution.
        try await Task.sleep(for: .milliseconds(1100))
        saver.stop()

        #expect(try manifest(of: project).updatedAt == created, "looking at a project is not a change")
    }

    @Test func stopSavesAtOnce() throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let project = store.create()
        let saver = ProjectAutosaver(project: project, store: store)

        project.title = "Closed"
        saver.stop()

        #expect(try manifest(of: project).title == "Closed")
    }
}
