import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Thin client over the three ElevenLabs endpoints the app needs.
/// An actor because it owns the voice cache, which several screens read concurrently.
public actor ElevenLabsClient {
    public static let defaultModelID = "eleven_multilingual_v2"

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let apiKey: @Sendable () -> String?
    private var cachedVoices: [Voice]?

    public init(
        baseURL: URL = URL(string: "https://api.elevenlabs.io")!,
        transport: any HTTPTransport = URLSession.shared,
        apiKey: @escaping @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.apiKey = apiKey
    }

    // MARK: - Endpoints

    public func voices(forceRefresh: Bool = false) async throws -> [Voice] {
        if let cachedVoices, !forceRefresh { return cachedVoices }
        let data = try await perform(path: "/v1/voices", method: "GET")
        let voices = try decode(VoicesResponse.self, from: data).voices
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cachedVoices = voices
        return voices
    }

    /// Text to speech with per-character timestamps, used to sync captions to the voice.
    public func speech(text: String, voiceID: String, modelID: String = defaultModelID) async throws -> Speech {
        let body = ["text": text, "model_id": modelID]
        let data = try await perform(
            path: "/v1/text-to-speech/\(voiceID)/with-timestamps",
            query: [URLQueryItem(name: "output_format", value: "mp3_44100_128")],
            method: "POST",
            json: body
        )
        let response = try decode(SpeechResponse.self, from: data)
        guard
            let audio = Data(base64Encoded: response.audioBase64),
            // `alignment` matches the original script; the normalized one spells out numbers etc.
            let alignment = response.alignment ?? response.normalizedAlignment
        else { throw ElevenLabsError.decoding }
        return Speech(audio: audio, alignment: alignment)
    }

    /// Sound effect generated from a text prompt. Returns MP3 data.
    public func soundEffect(prompt: String, durationSeconds: Double? = nil) async throws -> Data {
        var body: [String: any Sendable] = ["text": prompt]
        if let durationSeconds { body["duration_seconds"] = durationSeconds }
        return try await perform(path: "/v1/sound-generation", method: "POST", json: body)
    }

    // MARK: - Plumbing

    private func perform(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        json: [String: any Sendable]? = nil
    ) async throws -> Data {
        guard let key = apiKey(), !key.isEmpty else { throw ElevenLabsError.missingAPIKey }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw ElevenLabsError.network(error.code)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ElevenLabsError.from(status: status, body: data)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ElevenLabsError.decoding
        }
    }
}
