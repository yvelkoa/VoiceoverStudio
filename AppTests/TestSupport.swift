import Foundation
@testable import VoiceoverStudio

/// A fresh folder under the temporary directory, removed by the caller with `cleanUp()`.
struct TemporaryFolder {
    let url = URL.temporaryDirectory.appending(path: "VoiceoverStudioTests-\(UUID().uuidString)")

    init() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }

    /// An empty file inside the folder, standing in for a recording or an export.
    func file(_ name: String) -> URL {
        let file = url.appending(path: name)
        FileManager.default.createFile(atPath: file.path, contents: Data([0]))
        return file
    }
}

func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

/// Polls `condition` on the main actor until it holds or `timeout` passes; returns whether it held.
/// The steps under test run in unstructured tasks, so there is nothing to await directly.
@discardableResult
func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Suspends an operation until the test opens it, so a step can be held "running" deterministically.
final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    private(set) var isWaiting = false

    func wait() async {
        guard !isOpen else { return }
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
