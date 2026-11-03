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
