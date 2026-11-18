import Foundation
import Testing
@testable import VoiceoverStudio

/// One folder per project with a JSON manifest; the list is built from the manifests.
struct ProjectStoreTests {
    private let folder = TemporaryFolder()

    @Test func createdProjectIsSavedAndListed() throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)

        let project = store.create()

        #expect(exists(project.folder.appending(path: ProjectDocument.fileName)))
        #expect(store.summaries.map(\.id) == [project.id])
        #expect(try store.load(project.id).title == project.title)
    }

    @Test func savedChangesSurviveALoad() async throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let project = store.create()
        project.title = "Trailer"
        project.addCharacter(named: "Dog")

        try store.save(project)
        let loaded = try await store.loadInBackground(project.id)

        #expect(loaded.title == "Trailer")
        #expect(loaded.characters.map(\.name) == project.characters.map(\.name))
    }

    @Test func savingDoesNotWriteBackIntoTheProject() throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let project = store.create()
        let before = project.updatedAt

        try store.save(project)

        // A write-back here would make the autosaver see a change and save again forever.
        #expect(project.updatedAt == before)
    }

    @Test func renameAndDelete() throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let project = store.create()

        store.rename(project.id, to: "Renamed")
        #expect(try store.load(project.id).title == "Renamed")
        #expect(store.summaries.first?.title == "Renamed")

        store.delete(project.id)
        #expect(store.summaries.isEmpty)
        #expect(!exists(project.folder))
    }

    @Test func listIsNewestFirstAcrossRelaunches() async throws {
        defer { folder.cleanUp() }
        let store = ProjectStore(root: folder.url)
        let older = store.create()
        // The manifest stores `updatedAt` as ISO 8601 with whole seconds; two saves in one second tie.
        try await Task.sleep(for: .milliseconds(1100))
        let newer = store.create()

        let relaunched = ProjectStore(root: folder.url)

        #expect(relaunched.summaries.map(\.id) == [newer.id, older.id])
    }

    @Test func brokenManifestStaysVisibleAsUnreadable() throws {
        defer { folder.cleanUp() }
        let id = UUID()
        let broken = folder.url.appending(path: id.uuidString)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: broken.appending(path: ProjectDocument.fileName))

        let store = ProjectStore(root: folder.url)

        #expect(store.summaries.map(\.id) == [id])
        #expect(store.summaries.first?.isReadable == false)
    }

    @Test func foldersThatAreNotProjectsAreIgnored() throws {
        defer { folder.cleanUp() }
        try FileManager.default.createDirectory(at: folder.url.appending(path: "Inbox"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.url.appending(path: UUID().uuidString), withIntermediateDirectories: true
        )

        let store = ProjectStore(root: folder.url)

        #expect(store.summaries.isEmpty)
    }
}
