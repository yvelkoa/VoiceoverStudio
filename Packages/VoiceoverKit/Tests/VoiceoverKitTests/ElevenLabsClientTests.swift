import Foundation
import Testing
@testable import VoiceoverKit

struct ElevenLabsClientTests {
    @Test func voicesAreDecodedSortedAndCached() async throws {
        let transport = MockTransport(responses: [.init(status: 200, body: try fixture("voices"))])
        let client = ElevenLabsClient(transport: transport, apiKey: { "key" })

        let voices = try await client.voices()
        _ = try await client.voices()

        #expect(voices.map(\.name) == ["adam", "Rachel"])
        #expect(voices[0].labels == [:], "a non-string label must not break decoding")
        #expect(voices[1].summary == "american · young · female · narration")
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].value(forHTTPHeaderField: "xi-api-key") == "key")
    }

    @Test func speechDecodesAudioAndAlignment() async throws {
        let transport = MockTransport(responses: [.init(status: 200, body: try fixture("speech"))])
        let client = ElevenLabsClient(transport: transport, apiKey: { "key" })

        let speech = try await client.speech(text: "Hi there.", voiceID: "voice_a")

        #expect(speech.audio == Data("ID3".utf8))
        #expect(speech.alignment.characters.count == 9)
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/v1/text-to-speech/voice_a/with-timestamps")
        #expect(request.url?.query == "output_format=mp3_44100_128")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body == ["text": "Hi there.", "model_id": ElevenLabsClient.defaultModelID])
    }

    @Test func speechPassesVoiceSettingsWhenGiven() async throws {
        let transport = MockTransport(responses: [.init(status: 200, body: try fixture("speech"))])
        let client = ElevenLabsClient(transport: transport, apiKey: { "key" })

        _ = try await client.speech(text: "Hi", voiceID: "v", settings: VoiceSettings(stability: 0.3, speed: 1.1))

        let request = try #require(transport.requests.first)
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let settings = body?["voice_settings"] as? [String: Double]
        #expect(settings == ["stability": 0.3, "speed": 1.1], "nil fields are omitted, keys use snake_case")
    }

    @Test func changeVoiceUploadsMultipartForm() async throws {
        let transport = MockTransport(responses: [.init(status: 200, body: Data("ID3".utf8))])
        let client = ElevenLabsClient(transport: transport, apiKey: { "key" })
        let audio = Data([0x00, 0xFF, 0x0D, 0x0A, 0x2D, 0x2D])

        let result = try await client.changeVoice(
            audio: audio,
            fileName: "take.m4a",
            mimeType: "audio/mp4",
            voiceID: "voice_b",
            settings: VoiceSettings(stability: 0.3),
            removeBackgroundNoise: true
        )

        #expect(result == Data("ID3".utf8))
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/voice-changer/voice_b")
        #expect(request.url?.query == "output_format=mp3_44100_128")

        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(contentType.split(separator: "boundary=").last.map(String.init))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        let filePart = "Content-Disposition: form-data; name=\"audio\"; filename=\"take.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n"
        #expect(text.contains(filePart))
        #expect(text.contains("name=\"model_id\"\r\n\r\neleven_multilingual_sts_v2\r\n"))
        #expect(text.contains("name=\"remove_background_noise\"\r\n\r\ntrue\r\n"))
        #expect(text.contains("name=\"voice_settings\"\r\n\r\n{\"stability\":0.3}\r\n"))
        #expect(text.hasSuffix("--\(boundary)--\r\n"))
        #expect(body.range(of: audio) != nil, "binary audio is embedded unchanged")
    }

    @Test func missingKeyFailsWithoutNetwork() async {
        let transport = MockTransport(responses: [])
        let client = ElevenLabsClient(transport: transport, apiKey: { nil })

        await #expect(throws: ElevenLabsError.missingAPIKey) { try await client.voices() }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (401, #"{"detail":{"status":"invalid_api_key","message":"Invalid"}}"#, ElevenLabsError.invalidAPIKey),
        (401, #"{"detail":{"status":"quota_exceeded","message":"Out"}}"#, .quotaExceeded),
        (429, #"{"detail":{"status":"too_many_concurrent_requests"}}"#, .rateLimited),
        (422, #"{"detail":[{"msg":"text is too long"}]}"#, .invalidRequest("text is too long")),
        (500, "oops", .server(status: 500)),
    ])
    func httpErrorsMapToTypedErrors(status: Int, body: String, expected: ElevenLabsError) async {
        let transport = MockTransport(responses: [.init(status: status, body: Data(body.utf8))])
        let client = ElevenLabsClient(transport: transport, apiKey: { "key" })

        await #expect(throws: expected) { try await client.soundEffect(prompt: "door creak") }
    }

    @Test func offlineMapsToNetworkError() async {
        let transport = MockTransport(responses: [], error: URLError(.notConnectedToInternet))
        let client = ElevenLabsClient(transport: transport, apiKey: { "key" })

        await #expect(throws: ElevenLabsError.network(.notConnectedToInternet)) { try await client.voices() }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Response {
        let status: Int
        let body: Data
    }

    private let lock = NSLock()
    private var responses: [Response]
    private let error: URLError?
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    init(responses: [Response], error: URLError? = nil) {
        self.responses = responses
        self.error = error
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let next: Response = try lock.withLock {
            recorded.append(request)
            if let error { throw error }
            return responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (next.body, response)
    }
}
