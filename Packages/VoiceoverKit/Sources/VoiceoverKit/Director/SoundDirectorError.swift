import Foundation
import FoundationModels

/// Why the sound director couldn't suggest anything, each with a message the user can act on.
public enum SoundDirectorError: Error, Equatable, Sendable {
    case deviceNotEligible
    case appleIntelligenceOff
    case modelNotReady
    /// The words are in a language the on-device model doesn't read.
    case unsupportedLanguage
    /// No captions yet: nothing has been transcribed or generated.
    case nothingToRead
    case transcriptTooLong
    /// The model's safety guardrails declined the transcript.
    case declined
    /// Anything else, with the system's description.
    case failed(String)

    /// Classifies an error thrown while planning. Already-classified errors pass through.
    init(_ error: any Error) {
        if let error = error as? SoundDirectorError {
            self = error
            return
        }
        guard let error = error as? LanguageModelSession.GenerationError else {
            self = .failed(error.localizedDescription)
            return
        }
        switch error {
        case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
        case .exceededContextWindowSize: self = .transcriptTooLong
        case .assetsUnavailable: self = .modelNotReady
        case .guardrailViolation, .refusal: self = .declined
        default: self = .failed(error.localizedDescription)
        }
    }
}

extension SoundDirectorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .deviceNotEligible:
            String(localized: "This device can't run Apple Intelligence, which suggests the sounds.", bundle: .module)
        case .appleIntelligenceOff:
            String(localized: "Turn on Apple Intelligence in Settings to get sound suggestions.", bundle: .module)
        case .modelNotReady:
            String(localized: "Apple Intelligence is still getting ready. Try again in a few minutes.", bundle: .module)
        case .unsupportedLanguage:
            String(
                localized: """
                    Apple Intelligence can't read this language yet. \
                    Suggestions work for English and several other languages.
                    """,
                bundle: .module
            )
        case .nothingToRead:
            String(localized: "Nothing to read yet. Record a take or generate a voiceover first.", bundle: .module)
        case .transcriptTooLong:
            String(localized: "The transcript is too long for the on-device model.", bundle: .module)
        case .declined:
            String(localized: "Apple Intelligence declined to suggest sounds for this transcript.", bundle: .module)
        case .failed(let message):
            String(localized: "Couldn't suggest sounds: \(message)", bundle: .module)
        }
    }
}
