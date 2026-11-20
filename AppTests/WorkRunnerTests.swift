import Foundation
import Testing
import VoiceoverKit
@testable import VoiceoverStudio

/// The two task slots, deferred work and failure reporting. The review found its bugs here
/// (a compose cancelling a job, a job cancelling itself), so each rule gets a test.
struct WorkRunnerTests {
    private struct Boom: Error {}

    @Test func jobReportsActivityWhileRunningAndClearsItAfter() async {
        let runner = WorkRunner()
        let gate = Gate()

        runner.run(.exporting) { await gate.wait() }

        #expect(runner.activity == .exporting)
        #expect(runner.isBusy)

        gate.open()
        #expect(await eventually { !runner.isBusy })
        #expect(runner.activity == nil)
        #expect(runner.failure == nil)
    }

    @Test func newerComposeCancelsTheOlderOne() async {
        let runner = WorkRunner()
        var firstWasCancelled = false
        var secondFinished = false

        runner.run(.composing, slot: .compose) {
            do { try await Task.sleep(for: .seconds(10)) } catch { firstWasCancelled = true; throw error }
        }

        runner.run(.composing, slot: .compose) { secondFinished = true }

        #expect(await eventually { firstWasCancelled && secondFinished })
        #expect(runner.activity == nil)
        #expect(runner.failure == nil)
    }

    @Test func composeDoesNotCancelARunningJob() async {
        let runner = WorkRunner()
        let gate = Gate()
        var jobFinished = false

        runner.run(.swapping) {
            await gate.wait()
            try Task.checkCancellation()
            jobFinished = true
        }

        runner.run(.composing, slot: .compose) {}
        #expect(await eventually { gate.isWaiting })

        gate.open()
        #expect(await eventually { jobFinished })
        #expect(!runner.isBusy)
    }

    @Test func whenIdleRunsAtOnceWithoutAJob() {
        let runner = WorkRunner()
        var ran = false

        runner.whenIdle { ran = true }

        #expect(ran)
    }

    @Test func whenIdleWaitsForTheJobAndOnlyTheLatestStepRuns() async {
        let runner = WorkRunner()
        let gate = Gate()
        var steps: [String] = []

        runner.run(.swapping) { await gate.wait() }
        runner.whenIdle { steps.append("first") }
        runner.whenIdle { steps.append("second") }
        #expect(steps.isEmpty)

        gate.open()
        #expect(await eventually { !runner.isBusy })
        #expect(steps == ["second"])
    }

    @Test func cancelAllStopsTheJobAndRunsTheDeferredStep() async {
        let runner = WorkRunner()
        var jobWasCancelled = false
        var deferredRan = false

        runner.run(.swapping) {
            do { try await Task.sleep(for: .seconds(10)) } catch { jobWasCancelled = true; throw error }
        }
        runner.whenIdle { deferredRan = true }
        runner.cancelAll()

        #expect(deferredRan)
        #expect(!runner.isBusy)
        #expect(runner.activity == nil)
        #expect(await eventually { jobWasCancelled })
        #expect(runner.failure == nil)
    }

    @Test func elevenLabsErrorKeepsItsRecovery() async {
        let runner = WorkRunner()

        runner.run(.generating) { throw ElevenLabsError.invalidAPIKey }

        #expect(await eventually { runner.failure != nil })
        #expect(runner.failure?.recovery == .openSettings)
        #expect(runner.failure?.message == ElevenLabsError.invalidAPIKey.localizedDescription)
    }

    @Test func otherErrorsOfferARetryThatRepeatsTheStep() async {
        let runner = WorkRunner()
        var retried = false

        runner.run(.exporting, retry: { retried = true }, operation: { throw Boom() })

        #expect(await eventually { runner.failure != nil })
        #expect(runner.failure?.recovery == .retry)
        runner.failure?.retry?()
        #expect(retried)
    }

    @Test func cancellationIsNotAFailure() async {
        let runner = WorkRunner()

        runner.run(.exporting) { throw CancellationError() }

        #expect(await eventually { !runner.isBusy })
        #expect(runner.failure == nil)
    }
}
