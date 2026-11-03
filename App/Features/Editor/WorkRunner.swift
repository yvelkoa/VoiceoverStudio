import Foundation
import Observation
import VoiceoverKit

/// Runs the editor's steps one slot at a time and turns their errors into something the UI can act on.
///
/// Two slots: **compose** is cheap and restartable (a newer compose cancels an older one); a **job** spends
/// credits or minutes and is only ever stopped by `cancelAll()`. Work that must not interrupt a job
/// (`whenIdle`) waits until the job is done. The owner reads `activity`, `failure` and `isBusy`.
@Observable
final class WorkRunner {

    // MARK: - Types

    enum Activity: Equatable {
        case generating, generatingEffect, composing, exporting, swapping, saving
    }

    struct Failure: Identifiable {
        let id = UUID()
        let message: String
        let recovery: ElevenLabsError.Recovery
        /// Repeats exactly the step that failed (an export retry must not re-spend generation credits).
        /// Built from a weak reference to the owner and plain values only: a failure is stored here, the
        /// runner on the owner, so a retry that captured the operation (and through it the owner) would be a cycle.
        var retry: (() -> Void)?

        init(message: String, recovery: ElevenLabsError.Recovery, retry: (() -> Void)? = nil) {
            self.message = message
            self.recovery = recovery
            self.retry = retry
        }
    }

    enum Slot { case compose, job }

    // MARK: - State

    private(set) var activity: Activity?
    var failure: Failure?

    /// A job is running. Edits that would change its input wait (`whenIdle`) so it is never cancelled by
    /// accident; a cancelled swap has already been billed.
    var isBusy: Bool { jobTask != nil }

    private var composeTask: Task<Void, Never>?
    private var jobTask: Task<Void, Never>?
    /// The step handed to `whenIdle` while a job ran; the newest one wins.
    private var deferred: (@MainActor () -> Void)?

    isolated deinit {
        composeTask?.cancel()
        jobTask?.cancel()
    }

    // MARK: - Running

    /// Runs one step in its slot. `retry` must re-enter the owner's public method with values only
    /// (no captured operation), see `Failure.retry`.
    func run(
        _ activity: Activity,
        slot: Slot = .job,
        retry: (@MainActor () -> Void)? = nil,
        operation: @escaping () async throws -> Void
    ) {
        switch slot {
        case .compose: composeTask?.cancel()
        case .job: jobTask?.cancel()
        }
        self.activity = activity

        let task = Task {
            do {
                try await operation()
            } catch is CancellationError {
                // Cancelled or superseded; nothing to report.
            } catch {
                // AVFoundation and Photos report a cancelled task with their own errors; those are not failures.
                guard !Task.isCancelled else { return }
                let recovery = (error as? ElevenLabsError)?.recovery ?? .retry
                failure = Failure(message: error.localizedDescription, recovery: recovery, retry: retry)
            }
            if !Task.isCancelled { finish(slot) }
        }

        switch slot {
        case .compose: composeTask = task
        case .job: jobTask = task
        }
    }

    /// Runs `step` now, or once the current job has finished or been cancelled. Only the latest waits.
    func whenIdle(_ step: @escaping @MainActor () -> Void) {
        if isBusy {
            deferred = step
        } else {
            step()
        }
    }

    /// Stops whatever is running. The user asked for it, so a job's partial result is dropped on purpose.
    func cancelAll() {
        composeTask?.cancel()
        composeTask = nil
        jobTask?.cancel()
        jobTask = nil
        activity = nil

        runDeferred()
    }

    // MARK: - Private

    private func finish(_ slot: Slot) {
        activity = nil

        switch slot {
        case .compose:
            composeTask = nil
        case .job:
            jobTask = nil
            runDeferred()
        }
    }

    private func runDeferred() {
        guard let step = deferred else { return }
        deferred = nil
        step()
    }
}
