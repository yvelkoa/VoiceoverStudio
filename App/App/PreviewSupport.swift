#if DEBUG
import Foundation
import Synchronization

/// A key held in memory: previews and tests must not read or write the device's Keychain.
final class InMemoryKeyStore: APIKeyStoring {
    private let key: Mutex<String?>

    nonisolated init(_ key: String? = nil) {
        self.key = Mutex(key)
    }

    nonisolated func read() -> String? { key.withLock { $0 } }
    nonisolated func save(_ key: String) -> Bool {
        self.key.withLock { $0 = key }
        return true
    }
    nonisolated func delete() { key.withLock { $0 = nil } }
}

extension AppModel {
    /// An app with its own empty project folder and an in-memory key, for SwiftUI previews.
    static func preview(apiKey: String? = "preview-key", projects titles: [String] = []) -> AppModel {
        let root = URL.temporaryDirectory.appending(path: "Previews-\(UUID().uuidString)")
        let app = AppModel(keyStore: InMemoryKeyStore(apiKey), store: ProjectStore(root: root))
        for title in titles {
            let project = app.store.create()
            app.store.rename(project.id, to: title)
        }

        return app
    }
}
#endif
