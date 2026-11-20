import Foundation
import Observation
import VoiceoverKit

/// Sound suggestions from the on-device model: one plan at a time, streamed in so the sheet fills as the
/// model writes. Free and local, so it runs beside the editor's jobs instead of in `WorkRunner`'s job slot,
/// and a failure stays in the sheet rather than raising the editor's alert.
@Observable
final class SoundIdeas {
    /// The plan so far, or the finished one.
    private(set) var plan: SoundPlan?
    private(set) var isPlanning = false
    /// Why the last attempt produced nothing, in words for the user.
    private(set) var failure: String?

    private let planSounds: @Sendable ([Caption], Double, Locale?) -> AsyncThrowingStream<SoundPlan, any Error>
    private var task: Task<Void, Never>?

    init(services: EditorServices) {
        planSounds = services.planSounds
    }

    isolated deinit {
        task?.cancel()
    }

    /// Starts over from `captions`, dropping any plan being written.
    func suggest(from captions: [Caption], videoDuration: Double, locale: Locale?) {
        cancel()
        plan = nil
        failure = nil
        isPlanning = true

        let stream = planSounds(captions, videoDuration, locale)
        task = Task {
            do {
                for try await plan in stream {
                    guard !Task.isCancelled else { return }

                    self.plan = plan
                }

                // A cancelled consumer leaves the loop as if the stream had ended; this run was superseded
                // and must not report on the state the newer one owns.
                guard !Task.isCancelled else { return }

                if plan?.effects.isEmpty ?? true, plan?.musicPrompt.isEmpty ?? true {
                    failure = String(localized: "No ideas this time. Try again, or add sounds by hand.")
                }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }

                failure = error.localizedDescription
            }

            isPlanning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isPlanning = false
    }
}
