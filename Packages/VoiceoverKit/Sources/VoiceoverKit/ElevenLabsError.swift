import Foundation

/// Every failure the UI can meet, each with a message and a concrete recovery action.
public enum ElevenLabsError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case quotaExceeded
    case rateLimited
    case invalidRequest(String)
    case server(status: Int)
    case network(URLError.Code)
    case decoding

    public enum Recovery: Sendable {
        case openSettings, retry, editInput, none
    }

    public var recovery: Recovery {
        switch self {
        case .missingAPIKey, .invalidAPIKey: .openSettings
        case .rateLimited, .server, .network: .retry
        case .invalidRequest: .editInput
        case .quotaExceeded, .decoding: .none
        }
    }

    /// Maps an HTTP error response to a typed error.
    /// ElevenLabs returns `{"detail": {"status": "...", "message": "..."}}` for most failures
    /// and `{"detail": [{"msg": "..."}]}` for validation errors.
    static func from(status: Int, body: Data) -> ElevenLabsError {
        let detail = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.detail

        switch (status, detail?.status) {
        case (_, "quota_exceeded"): return .quotaExceeded
        case (401, _), (_, "invalid_api_key"): return .invalidAPIKey
        case (429, _): return .rateLimited
        case (400, _), (422, _): return .invalidRequest(detail?.message ?? "The request was rejected.")
        default: return .server(status: status)
        }
    }
}

extension ElevenLabsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your ElevenLabs API key to get started."
        case .invalidAPIKey: "Your API key was rejected. Check it in Settings."
        case .quotaExceeded: "You've used up your ElevenLabs credits for this period."
        case .rateLimited: "Too many requests right now. Try again in a moment."
        case .invalidRequest(let message): message
        case .server(let status): "ElevenLabs is having trouble (HTTP \(status)). Try again."
        case .network: "No connection to ElevenLabs. Check your network and retry."
        case .decoding: "Got an unexpected response from ElevenLabs."
        }
    }
}

private struct ErrorBody: Decodable {
    struct Detail: Decodable {
        let status: String?
        let message: String?
    }

    let detail: Detail?

    enum CodingKeys: String, CodingKey { case detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let object = try? c.decode(Detail.self, forKey: .detail) {
            detail = object
        } else if let list = try? c.decode([ValidationItem].self, forKey: .detail) {
            detail = Detail(status: "validation_error", message: list.first?.msg)
        } else {
            detail = nil
        }
    }

    private struct ValidationItem: Decodable { let msg: String? }
}
