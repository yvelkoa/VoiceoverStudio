import Foundation
import Shared
import Testing
import VoiceoverKit

/// How a Kotlin `suspend` function and a sealed error hierarchy look from Swift. No network is involved:
/// without a key both clients fail before sending anything.
struct SuspendBridgingTests {
    @Test func suspendFunctionIsAwaitableAndThrowsTheSealedCase() async {
        let client = Shared.ElevenLabsClient(apiKey: { nil })

        do {
            _ = try await client.voices(forceRefresh: false)
            Issue.record("expected the call to throw")
        } catch {
            // The Kotlin exception arrives as an NSError; the typed case is one cast away, in userInfo.
            let kotlinError = (error as NSError).userInfo["KotlinException"]
            #expect(kotlinError is Shared.ElevenLabsError.MissingApiKey)
            #expect((kotlinError as? Shared.ElevenLabsError)?.recovery == .openSettings)
        }
    }

    @Test func swiftReferenceThrowsTheMatchingEnumCase() async {
        let client = VoiceoverKit.ElevenLabsClient(apiKey: { nil })

        await #expect(throws: VoiceoverKit.ElevenLabsError.missingAPIKey) { try await client.voices() }
        #expect(VoiceoverKit.ElevenLabsError.missingAPIKey.recovery == .openSettings)
    }
}
