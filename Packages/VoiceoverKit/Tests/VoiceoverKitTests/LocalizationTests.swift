import Foundation
import Testing
@testable import VoiceoverKit

/// Error messages are shown as-is by the app, so the package ships its own translations.
struct LocalizationTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(PackageResources.bundle.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test(arguments: ["ru", "uk"])
    func everyErrorIsTranslated(language: String) throws {
        let bundle = try bundle(language)
        let english = "Your API key was rejected. Check it in Settings."

        let translated = String(localized: "Your API key was rejected. Check it in Settings.", bundle: bundle)

        #expect(translated != english)
        #expect(!translated.isEmpty)
    }
}
