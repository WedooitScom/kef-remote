import Foundation
import Testing
@testable import KEFKit

/// String Catalogs de KEFKit et de l'app : chaque clé traduite dans les cinq langues, avec
/// les mêmes arguments (%@, %lld…) que la clé française.
@Suite("Traductions")
struct LocalizationTests {
    static let languages = ["en", "es", "it", "ja"]
    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")
    static let catalogs = ["KEFKit/Localizable.xcstrings", "KEFRemote/Localizable.xcstrings",
                           "KEFRemote/InfoPlist.xcstrings"]

    struct Entry {
        var catalog: String
        var key: String
        var json: [String: Any]
    }

    static func entries(_ catalog: String) throws -> [Entry] {
        let data = try Data(contentsOf: sources.appendingPathComponent(catalog))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "fr")
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        return strings.map { Entry(catalog: catalog, key: $0.key, json: $0.value) }.sorted { $0.key < $1.key }
    }

    /// Valeurs d'une traduction : chaîne simple, ou chaque forme du pluriel.
    static func values(_ localization: Any?) -> [String] {
        guard let localization = localization as? [String: Any] else { return [] }
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [value]
        }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return plural.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
    }

    /// Types des arguments, dans l'ordre (positions explicites « %2$@ » comprises).
    static func arguments(_ format: String) -> [String] {
        let regex = /%(?:(\d)\$)?(lld|ld|d|@|lf|f)/
        var result: [Int: String] = [:]
        for (index, match) in format.matches(of: regex).enumerated() {
            let position = match.output.1.flatMap { Int($0) } ?? index + 1
            result[position] = String(match.output.2)
        }
        return result.keys.sorted().map { result[$0]! }
    }

    @Test(arguments: catalogs)
    func everyKeyIsTranslated(_ catalog: String) throws {
        let entries = try Self.entries(catalog)
        #expect(!entries.isEmpty)
        for entry in entries {
            let localizations = entry.json["localizations"] as? [String: Any] ?? [:]
            for language in Self.languages {
                let values = Self.values(localizations[language])
                #expect(!values.isEmpty && values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                        "\(entry.catalog) : « \(entry.key) » sans traduction \(language)")
            }
            // Pluriels et Info.plist : le français est aussi dans le catalogue.
            if localizations["fr"] != nil || catalog.hasPrefix("KEFRemote/InfoPlist") {
                #expect(!Self.values(localizations["fr"]).isEmpty, "\(entry.catalog) : « \(entry.key) » sans français")
            }
        }
    }

    @Test(arguments: catalogs.filter { $0.hasSuffix("Localizable.xcstrings") })
    func translationsKeepTheArguments(_ catalog: String) throws {
        for entry in try Self.entries(catalog) {
            let expected = Self.arguments(entry.key)
            let localizations = entry.json["localizations"] as? [String: Any] ?? [:]
            for (language, localization) in localizations {
                let isPlural = (localization as? [String: Any])?["variations"] != nil
                for value in Self.values(localization) {
                    // Forme « one » d'un pluriel : le nombre peut être omis (« une station »).
                    if isPlural && Self.arguments(value).isEmpty { continue }
                    #expect(Self.arguments(value) == expected, "\(language) : « \(value) » pour « \(entry.key) »")
                }
            }
        }
    }

    @Test func designNamesAreTranslated() throws {
        // Tables compilées par SwiftPM : chaque langue a la sienne, la clé française sert de repli.
        for language in Self.languages {
            let bundle = KEFLocalization.bundle(for: language)
            #expect(bundle.bundlePath.hasSuffix("\(language).lproj"), "\(bundle.bundlePath)")
        }
        #expect(KEFLocalization.string("Rétro pixel", language: "ja") == "レトロピクセル")
        #expect(KEFLocalization.string("Toutes les stations", language: "it") == "Tutte le stazioni")
        #expect(KEFLocalization.string("Classique", language: "en") == "Classic")
        #expect(KEFLocalization.string("Classique", language: "es") == "Clásico")
        #expect(KEFLocalization.string("Classique", language: "fr") == "Classique")
        // Arguments : positions explicites, ponctuation propre à chaque langue.
        let code = 503
        #expect(KEFLocalization.string("Erreur HTTP \(code)", language: "ja") == "HTTPエラー 503")
        #expect(KEFLocalization.string("Erreur HTTP \(code)", language: "fr") == "Erreur HTTP 503")
        let label = "Langue", value = "français"
        #expect(KEFLocalization.string("\(label) : \(value)", language: "en") == "Langue: français")
        #expect(KEFLocalization.string("\(label) : \(value)", language: "ja") == "Langue：français")
    }

    @Test func testsRunInTheDevelopmentLanguage() {
        // Hors du bundle .app, KEFKit reste en français, quelle que soit la langue du Mac.
        #expect(KEFLocalization.language == "fr")
        #expect(AppDesign.classique.label == "Classique")
        #expect(KEFLocalization.supportedLanguages == ["fr", "en", "es", "it", "ja"])
    }
}
