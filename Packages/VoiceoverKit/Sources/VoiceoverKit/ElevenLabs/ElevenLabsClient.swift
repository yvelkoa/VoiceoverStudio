import Foundation

/// Thin client over the ElevenLabs endpoints the app needs.
/// An actor because it owns the voice cache, which several screens read concurrently.
public actor ElevenLabsClient {
    public static let defaultModelID = "eleven_multilingual_v2"
    public static let defaultVoiceChangerModelID = "eleven_multilingual_sts_v2"
    static let outputFormat = "mp3_44100_128"

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let apiKey: @Sendable () -> String?
    private var cachedVoices: [Voice]?

    /// The voice changer uploads a whole take and waits for the conversion; the default 60 s request timeout
    /// is tight for a long take on a slow link.
    public static let defaultTransport: any HTTPTransport = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration)
    }()

    public init(
        baseURL: URL = URL(string: "https://api.elevenlabs.io")!,
        transport: any HTTPTransport = ElevenLabsClient.defaultTransport,
        apiKey: @escaping @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.apiKey = apiKey
    }

    // MARK: - Endpoints

    /// Forgets the cached voice list, e.g. when the key is removed; the next `voices()` fetches again.
    public func clearCache() {
        cachedVoices = nil
    }

    public func voices(forceRefresh: Bool = false) async throws -> [Voice] {
        if let cachedVoices, !forceRefresh { return cachedVoices }
        let data = try await perform(path: "/v1/voices", method: "GET")
        let voices = try decode(VoicesResponse.self, from: data).voices
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cachedVoices = voices
        return voices
    }

    /// Text to speech with per-character timestamps, used to sync captions to the voice.
    public func speech(
        text: String,
        voiceID: String,
        modelID: String = defaultModelID,
        settings: VoiceSettings? = nil
    ) async throws -> Speech {
        var body: [String: any Sendable] = ["text": text, "model_id": modelID]
        if let settings {
            body["voice_settings"] = settings.jsonObject
        }
        let data = try await perform(
            path: "/v1/text-to-speech/\(voiceID)/with-timestamps",
            query: [URLQueryItem(name: "output_format", value: Self.outputFormat)],
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

    /// Instrumental music composed from a text prompt, `seconds` long (the API accepts 3 s to 10 min).
    /// Returns MP3 data. Composing takes a while, so the request waits longer than the others.
    public func music(prompt: String, seconds: Double) async throws -> Data {
        let milliseconds = Int((min(max(seconds, Self.musicLength.lowerBound), Self.musicLength.upperBound) * 1000).rounded())
        let body: [String: any Sendable] = [
            "prompt": prompt,
            "music_length_ms": milliseconds,
            "force_instrumental": true,
        ]
        return try await perform(
            path: "/v1/music",
            query: [URLQueryItem(name: "output_format", value: Self.outputFormat)],
            method: "POST",
            json: body,
            timeout: 300
        )
    }

    /// Lengths the music endpoint accepts, in seconds.
    public static let musicLength: ClosedRange<Double> = 3...600

    /// Speech to speech: the same words, timing and emotion as `audio`, spoken by `voiceID`. Returns MP3 data.
    /// Timing is preserved closely but not exactly; callers should compare durations.
    public func changeVoice(
        audio: Data,
        fileName: String,
        mimeType: String,
        voiceID: String,
        modelID: String = defaultVoiceChangerModelID,
        settings: VoiceSettings? = .expressive,
        removeBackgroundNoise: Bool = false
    ) async throws -> Data {
        var form = MultipartForm()
        form.addFile("audio", fileName: fileName, mimeType: mimeType, data: audio)
        form.addField("model_id", value: modelID)
        form.addField("remove_background_noise", value: removeBackgroundNoise ? "true" : "false")
        if let settings {
            let json = try JSONEncoder().encode(settings)
            form.addField("voice_settings", value: String(bytes: json, encoding: .utf8) ?? "{}")
        }
        return try await perform(
            path: "/v1/voice-changer/\(voiceID)",
            query: [URLQueryItem(name: "output_format", value: Self.outputFormat)],
            method: "POST",
            body: form.encoded(),
            contentType: form.contentType
        )
    }

    // MARK: - Plumbing

    private func perform(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        json: [String: any Sendable]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        try await perform(
            path: path,
            query: query,
            method: method,
            body: json.map { try JSONSerialization.data(withJSONObject: $0) },
            contentType: json == nil ? nil : "application/json",
            timeout: timeout
        )
    }

    private func perform(
        path: String,
        query: [URLQueryItem],
        method: String,
        body: Data?,
        contentType: String?,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        guard let key = apiKey(), !key.isEmpty else { throw ElevenLabsError.missingAPIKey }

        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw ElevenLabsError.invalidRequest("Malformed request path.")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw ElevenLabsError.invalidRequest("Malformed request URL.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeout { request.timeoutInterval = timeout }
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        if let body {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
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
