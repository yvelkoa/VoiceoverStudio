import AVFoundation
import Speech
import VoiceoverKit

/// The language takes are spoken in. Stored in UserDefaults; defaults to the device language.
enum RecordingLanguage {
    static let key = "recordingLanguage"
    static let choices = ["en-US", "ru-RU", "uk-UA", "de-DE", "es-ES", "fr-FR", "it-IT", "pt-BR", "ja-JP"]

    static var locale: Locale {
        if let id = UserDefaults.standard.string(forKey: key), !id.isEmpty {
            return Locale(identifier: id)
        }
        return Locale.current
    }
}
