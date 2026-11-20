import AVFoundation
import Foundation
import Synchronization
import VoiceoverKit
@testable import VoiceoverStudio

/// Answers requests from a queue and records them; the network seam of `ElevenLabsClient`.
nonisolated final class StubTransport: HTTPTransport {
    private let state: Mutex<(responses: [(Int, Data)], requests: [URLRequest])>

    init(_ responses: [(status: Int, body: Data)]) {
        state = Mutex((responses.map { ($0.status, $0.body) }, []))
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (status, body) = state.withLock { state in
            state.requests.append(request)
            return state.responses.isEmpty ? (500, Data()) : state.responses.removeFirst()
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!

        return (body, response)
    }
}

/// A value several stub closures write to; Sendable so `@Sendable` services can hold it.
nonisolated final class Recorder<Value: Sendable>: Sendable {
    private let storage: Mutex<[Value]>
    init() { storage = Mutex([]) }
    func append(_ value: Value) { storage.withLock { $0.append(value) } }
    var values: [Value] { storage.withLock { $0 } }
    var count: Int { values.count }
}

struct StubFailure: Error {}

extension EditorServices {
    /// Services that touch no media: composing yields an empty edit, exports write a one-byte file, every
    /// file is `duration` seconds long. Tests override the closures they observe.
    static func stub(duration: Double = 1) -> EditorServices {
        EditorServices(
            compose: { _, _ in emptyEdit() },
            export: { _, _, _, _, output in
                FileManager.default.createFile(atPath: output.path, contents: Data([0]))
                return output
            },
            saveToPhotos: { _ in },
            transcribe: { _, _ in [] },
            recordingLocale: { Locale(identifier: "en-US") },
            waveform: { _ in Waveform(peaks: []) },
            duration: { _ in duration },
            writeThumbnail: { _, _ in },
            planSounds: { _, _, _ in AsyncThrowingStream { $0.finish(throwing: SoundDirectorError.deviceNotEligible) } },
            prewarmSoundDirector: {}
        )
    }

    nonisolated static func emptyEdit() -> ComposedVideo {
        ComposedVideo(
            composition: AVMutableComposition(),
            trackKinds: [:],
            videoConfiguration: AVVideoComposition.Configuration()
        )
    }
}
