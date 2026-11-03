import AVFoundation
import VoiceoverKit

/// Sends takes through ElevenLabs speech-to-speech, a few at a time.
nonisolated enum VoiceSwapper {
    struct Job: Sendable {
        let take: Take
        let voiceID: String
        let settings: VoiceSettings
    }

    struct Outcome: Sendable {
        let takeID: Take.ID
        let audio: URL
        /// Converted length minus the original. ElevenLabs keeps timing closely, but not exactly.
        let drift: Double
    }

    /// Too many parallel requests hit the rate limit on small plans.
    static let maxConcurrentRequests = 3

    /// Converts every job and reports each outcome as soon as it lands, so the UI can update per take.
    static func convert(
        _ jobs: [Job],
        client: ElevenLabsClient,
        into directory: URL,
        onOutcome: @MainActor @Sendable (Outcome) -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Outcome.self) { group in
            var pending = jobs[...]
            for job in pending.prefix(maxConcurrentRequests) {
                group.addTask { try await convert(job, client: client, into: directory) }
            }
            pending = pending.dropFirst(maxConcurrentRequests)

            for try await outcome in group {
                await onOutcome(outcome)
                if let next = pending.popFirst() {
                    group.addTask { try await convert(next, client: client, into: directory) }
                }
            }
        }
    }

    private static func convert(_ job: Job, client: ElevenLabsClient, into directory: URL) async throws -> Outcome {
        let recording = try Data(contentsOf: job.take.recording)
        let converted = try await client.changeVoice(
            audio: recording,
            fileName: job.take.recording.lastPathComponent,
            mimeType: "audio/mp4",
            voiceID: job.voiceID,
            settings: job.settings,
            removeBackgroundNoise: true
        )
        try Task.checkCancellation()

        let url = directory.appending(path: "swapped-\(job.take.id.uuidString).mp3")
        try converted.write(to: url)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        return Outcome(takeID: job.take.id, audio: url, drift: duration - job.take.duration)
    }
}
