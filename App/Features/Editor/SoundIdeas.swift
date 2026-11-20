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

    /// How long a plan may take. The on-device model usually answers in 10 to 40 seconds, but now and then it
    /// keeps going past a minute without finishing; nobody should watch a spinner that long.
    private let timeLimit: Duration

    init(services: EditorServices, timeLimit: Duration = .seconds(45)) {
        planSounds = services.planSounds
        self.timeLimit = timeLimit
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
        let timeLimit = timeLimit
        task = Task {
            let reader = Task {
                for try await plan in stream {
                    try Task.checkCancellation()
                    self.plan = plan
                }
            }

            // Cancelling the reader ends the stream, which stops the model.
            let timer = Task {
                do {
                    try await Task.sleep(for: timeLimit)
                } catch {
                    return false
                }

                reader.cancel()
                return true
            }

            let result = await withTaskCancellationHandler {
                await reader.result
            } onCancel: {
                reader.cancel()
                timer.cancel()
            }

            timer.cancel()
            let ranOutOfTime = await timer.value

            // This run was superseded and must not report on the state the newer one owns.
            guard !Task.isCancelled else { return }

            if ranOutOfTime {
                // What the model wrote before the limit is a usable plan; only an empty one is a failure.
                if isEmpty { failure = String(localized: "Apple Intelligence took too long. Try again.") }
            } else {
                switch result {
                case .success:
                    if isEmpty { failure = String(localized: "No ideas this time. Try again, or add sounds by hand.") }
                case .failure(let error):
                    failure = error.localizedDescription
                }
            }

            isPlanning = false
        }
    }

    private var isEmpty: Bool {
        (plan?.effects.isEmpty ?? true) && (plan?.musicPrompt.isEmpty ?? true)
    }

    func cancel() {
        task?.cancel()
        task = nil
        isPlanning = false
    }
}
