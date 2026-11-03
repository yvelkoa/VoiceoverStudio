import Foundation
import VoiceoverKit

/// One transcription task per take, running beside everything else. Results and failures are handed back
/// through the two callbacks; cancelling a take's task (deleted take, deleted character, closed editor)
/// stops its recogniser too.
final class TranscriptionQueue {
    private var tasks: [Take.ID: Task<Void, Never>] = [:]

    /// Words for a take, timed from the start of its recording.
    var onWords: ((Take.ID, [TimedWord]) -> Void)?
    /// The take whose transcription failed, so the owner can offer a retry for exactly that take.
    var onFailure: ((Take, any Error) -> Void)?

    isolated deinit {
        cancelAll()
    }

    func transcribe(_ take: Take, locale: Locale = RecordingLanguage.locale) {
        tasks[take.id]?.cancel()
        tasks[take.id] = Task {
            defer { tasks[take.id] = nil }

            do {
                let words = try await Transcriber.words(in: take.recording, locale: locale)
                guard !Task.isCancelled else { return }
                onWords?(take.id, words)
            } catch is CancellationError {
                // The take was deleted or the editor closed.
            } catch {
                onFailure?(take, error)
            }
        }
    }

    func cancel(_ id: Take.ID) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    func cancel<IDs: Sequence>(_ ids: IDs) where IDs.Element == Take.ID {
        for id in ids { cancel(id) }
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
    }
}
