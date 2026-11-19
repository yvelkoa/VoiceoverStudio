import Foundation
import Testing
import VoiceoverKit
@testable import VoiceoverStudio

/// The composition root, built with an in-memory key, a temporary store and a stub network.
struct AppModelTests {
    private let folder = TemporaryFolder()

    private func makeApp(key: String?, _ responses: [(status: Int, body: Data)]) -> (AppModel, InMemoryKeyStore) {
        let keys = InMemoryKeyStore(key)
        let app = AppModel(keyStore: keys, store: ProjectStore(root: folder.url), transport: StubTransport(responses))
        return (app, keys)
    }

    @Test func aWorkingKeyIsKept() async throws {
        defer { folder.cleanUp() }
        let (app, keys) = makeApp(key: nil, [(200, Data(#"{"voices": []}"#.utf8))])

        try await app.saveAndVerify("  new-key \n")

        #expect(keys.read() == "new-key")
        #expect(app.hasAPIKey)
    }

    @Test func aRejectedKeyGivesBackThePreviousOne() async {
        defer { folder.cleanUp() }
        let (app, keys) = makeApp(key: "old-key", [(401, Data(#"{"detail": {"status": "invalid_api_key"}}"#.utf8))])

        await #expect(throws: ElevenLabsError.invalidAPIKey) { try await app.saveAndVerify("typo") }

        #expect(keys.read() == "old-key")
        #expect(app.hasAPIKey)
    }

    @Test func aRejectedFirstKeyLeavesNoKey() async {
        defer { folder.cleanUp() }
        let (app, keys) = makeApp(key: nil, [(401, Data())])

        await #expect(throws: ElevenLabsError.invalidAPIKey) { try await app.saveAndVerify("typo") }

        #expect(keys.read() == nil)
        #expect(!app.hasAPIKey)
    }

    @Test func aNetworkFailureKeepsTheNewKey() async {
        defer { folder.cleanUp() }
        let (app, keys) = makeApp(key: nil, [(503, Data())])

        await #expect(throws: ElevenLabsError.server(status: 503)) { try await app.saveAndVerify("new-key") }

        #expect(keys.read() == "new-key", "the key itself may be fine; only the check failed")
    }

    @Test func editorsShareTheAppsServices() {
        defer { folder.cleanUp() }
        let (app, _) = makeApp(key: "key", [])

        let editor = app.editor(for: app.store.create())

        #expect(editor.client === app.client)
    }
}
