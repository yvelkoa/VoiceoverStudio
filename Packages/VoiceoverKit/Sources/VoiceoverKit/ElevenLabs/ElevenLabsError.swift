import Foundation

/// Every failure the UI can meet, each with a message and a concrete recovery action.
public enum ElevenLabsError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKey
    /// The key is valid but wasn't granted the permission this endpoint needs; the message names it.
    case missingPermission(String)
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
        case .missingAPIKey, .invalidAPIKey:
            .openSettings
        case .rateLimited, .server, .network:
            .retry
        case .invalidRequest:
            .editInput
        case .missingPermission, .quotaExceeded, .decoding:
            .none
        }
    }

    /// Maps an HTTP error response to a typed error.
    /// ElevenLabs returns `{"detail": {"status": "...", "message": "..."}}` for most failures
    /// and `{"detail": [{"msg": "..."}]}` for validation errors.
    static func from(status: Int, body: Data) -> ElevenLabsError {
        let detail = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.detail

        switch (status, detail?.status) {
        case (_, "quota_exceeded"):
            return .quotaExceeded
        case (_, "missing_permissions"):
            let fallback = String(localized: "The API key is missing a permission this feature needs.", bundle: .module)
            return .missingPermission(detail?.message ?? fallback)
        case (401, _), (_, "invalid_api_key"):
            return .invalidAPIKey
        case (429, _):
            return .rateLimited
        case (400, _), (422, _):
            return .invalidRequest(detail?.message ?? String(localized: "The request was rejected.", bundle: .module))
        default:
            return .server(status: status)
        }
    }
}

extension ElevenLabsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(localized: "Add your ElevenLabs API key to get started.", bundle: .module)
        case .invalidAPIKey:
            String(localized: "Your API key was rejected. Check it in Settings.", bundle: .module)
        case .missingPermission(let message):
            message + " "
                + String(localized: "Edit the key's permissions at elevenlabs.io → Developers → API Keys.", bundle: .module)
        case .quotaExceeded:
            String(localized: "You've used up your ElevenLabs credits for this period.", bundle: .module)
        case .rateLimited:
            String(localized: "Too many requests right now. Try again in a moment.", bundle: .module)
        case .invalidRequest(let message):
            message
        case .server(let status):
            String(localized: "ElevenLabs is having trouble (HTTP \(status)). Try again.", bundle: .module)
        case .network:
            String(localized: "No connection to ElevenLabs. Check your network and retry.", bundle: .module)
        case .decoding:
            String(localized: "Got an unexpected response from ElevenLabs.", bundle: .module)
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
