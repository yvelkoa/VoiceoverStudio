import Foundation
import Observation
import VoiceoverKit

/// The user's own ElevenLabs key. Lives only in the Keychain; never in the bundle or the repo.
nonisolated struct APIKeyStore: Sendable {
    private let keychain = KeychainStore(service: "dev.velko.VoiceoverStudio")
    private let account = "elevenlabs-api-key"

    func read() -> String? { keychain.read(account) }
    func save(_ key: String) -> Bool { keychain.save(key, for: account) }
    func delete() { keychain.delete(account) }
}

@Observable
final class AppModel {
    let client: ElevenLabsClient
    let store = ProjectStore()
    private(set) var hasAPIKey: Bool

    private let keyStore: APIKeyStore

    init(keyStore: APIKeyStore = APIKeyStore()) {
        self.keyStore = keyStore
        self.hasAPIKey = keyStore.read() != nil
        self.client = ElevenLabsClient(apiKey: { keyStore.read() })
        AudioSession.activatePlayback()
    }

    /// Saves the key and checks it with a cheap request, so a typo shows up here and not mid-generation.
    func saveAndVerify(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyStore.save(trimmed) else { throw ElevenLabsError.missingAPIKey }
        hasAPIKey = true
        _ = try await client.voices(forceRefresh: true)
    }

    func removeKey() {
        keyStore.delete()
        hasAPIKey = false
    }
}
