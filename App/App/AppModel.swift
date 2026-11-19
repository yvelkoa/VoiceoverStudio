import Foundation
import Observation
import VoiceoverKit

/// The composition root: builds the app-wide dependencies once and hands them to the screens through the
/// environment. Every dependency comes in through `init`, so tests and previews build one with a temporary
/// store, an in-memory key, a stub transport and stub media services. Nothing here has side effects.
@Observable
final class AppModel {
    let client: ElevenLabsClient
    let store: ProjectStore
    /// Passed to every editor; see `EditorServices`.
    let services: EditorServices
    private(set) var hasAPIKey: Bool

    private let keyStore: any APIKeyStoring

    init(
        keyStore: any APIKeyStoring = APIKeyStore(),
        store: ProjectStore = ProjectStore(),
        transport: any HTTPTransport = ElevenLabsClient.defaultTransport,
        services: EditorServices = .live
    ) {
        self.keyStore = keyStore
        self.store = store
        self.services = services
        hasAPIKey = keyStore.read() != nil
        client = ElevenLabsClient(transport: transport, apiKey: { keyStore.read() })
    }

    /// Opens an editor on a loaded project with the app's client, store and services.
    func editor(for project: Project) -> EditorModel {
        EditorModel(project: project, client: client, store: store, services: services)
    }

    /// Saves the key and checks it with a cheap request, so a typo shows up here and not mid-generation.
    /// A rejected key is removed again; a network failure keeps it, since the key itself may well be fine.
    func saveAndVerify(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = keyStore.read()
        guard keyStore.save(trimmed) else { throw ElevenLabsError.missingAPIKey }
        hasAPIKey = true
        do {
            _ = try await client.voices(forceRefresh: true)
        } catch ElevenLabsError.invalidAPIKey {
            if let previous { _ = keyStore.save(previous) } else { removeKey() }
            throw ElevenLabsError.invalidAPIKey
        }
    }

    func removeKey() {
        keyStore.delete()
        hasAPIKey = false
        Task { await client.clearCache() }
    }
}
