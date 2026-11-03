import Foundation
import Observation
import VoiceoverKit

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
        AudioSession.configurePlayback()
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
