import Foundation
import Testing
@testable import VoiceoverStudio

/// The catalogs are filled by `Scripts/strings.sh` and checked for gaps by `Scripts/check.sh`; these tests
/// make sure the translations actually reach the built app, plural rules included.
struct LocalizationTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func takes(_ count: Int, in language: String) throws -> String {
        let format = NSLocalizedString("%lld takes", bundle: try bundle(language), comment: "")
        return String(format: format, locale: Locale(identifier: language), count)
    }

    @Test func appShipsRussianAndUkrainian() {
        #expect(Set(Bundle.main.localizations).isSuperset(of: ["en", "ru", "uk"]))
    }

    @Test(arguments: ["ru", "uk"])
    func interfaceIsTranslated(language: String) throws {
        let settings = String(localized: "Settings", bundle: try bundle(language))

        #expect(settings != "Settings")
    }

    @Test func russianTakesUseAllThreePluralForms() throws {
        #expect(try takes(1, in: "ru") == "1 дубль")
        #expect(try takes(3, in: "ru") == "3 дубля")
        #expect(try takes(5, in: "ru") == "5 дублей")
        #expect(try takes(21, in: "ru") == "21 дубль")
    }

    @Test func ukrainianTakesUseAllThreePluralForms() throws {
        #expect(try takes(1, in: "uk") == "1 дубль")
        #expect(try takes(3, in: "uk") == "3 дублі")
        #expect(try takes(5, in: "uk") == "5 дублів")
    }

    @Test func englishTakesAreSingularForOne() throws {
        #expect(try takes(1, in: "en") == "1 take")
        #expect(try takes(2, in: "en") == "2 takes")
    }

    @Test(arguments: ["ru", "uk"])
    func packageErrorsAreTranslatedInTheApp(language: String) throws {
        let kit = try #require(Bundle.main.url(forResource: "VoiceoverKit_VoiceoverKit", withExtension: "bundle"))
        let path = try #require(Bundle(url: kit)?.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))

        let message = String(localized: "The request was rejected.", bundle: bundle)

        #expect(message != "The request was rejected.")
    }
}
