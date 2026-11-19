import Foundation
import Observation
import VoiceoverKit

/// Where the ElevenLabs key is kept. A protocol so tests and previews can hold a key in memory instead of
/// touching the device's Keychain.
nonisolated protocol APIKeyStoring: Sendable {
    func read() -> String?
    func save(_ key: String) -> Bool
    func delete()
}

/// The user's own ElevenLabs key. Lives only in the Keychain; never in the bundle or the repo.
nonisolated struct APIKeyStore: APIKeyStoring {
    private let keychain = KeychainStore(service: "dev.velko.VoiceoverStudio")
    private let account = "elevenlabs-api-key"

    func read() -> String? { keychain.read(account) }
    func save(_ key: String) -> Bool { keychain.save(key, for: account) }
    func delete() { keychain.delete(account) }
}
