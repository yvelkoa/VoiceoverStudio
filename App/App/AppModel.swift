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
