import Foundation

/// Langue de l'interface et accès aux chaînes traduites de KEFKit (`Localizable.xcstrings`).
///
/// Dans l'app, la langue est celle que macOS retient pour le bundle principal (préférences
/// système, réglage « Langue » de l'app via `AppleLanguages`, ou `-AppleLanguages "(ja)"`).
/// Hors app (tests, `swift run`), on reste en français, langue de développement : les
/// résultats ne dépendent pas de la langue du Mac.
public enum KEFLocalization {
    /// Langues de l'interface, langue de développement en tête.
    public static let supportedLanguages = ["fr", "en", "es", "it", "ja"]
    public static let developmentLanguage = "fr"

    /// Langue retenue pour ce lancement (code court : « fr », « ja »…).
    public static let language: String = {
        let main = Bundle.main
        guard main.bundleURL.pathExtension == "app" else { return developmentLanguage }
        let preferred = Bundle.preferredLocalizations(from: supportedLanguages,
                                                      forPreferences: main.preferredLocalizations)
        return preferred.first ?? developmentLanguage
    }()

    /// Locale de l'interface (formats de nombres, majuscules) : langue de l'interface, région du Mac.
    public static let locale: Locale = {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        return Locale(components: components)
    }()

    /// Table de KEFKit pour une langue donnée (sous-bundle `<langue>.lproj` du bundle de
    /// ressources) ; le bundle lui-même (clés françaises) si la langue n'a pas de dossier.
    public static func bundle(for language: String) -> Bundle {
        let base = Bundle.module
        if let path = base.path(forResource: language, ofType: "lproj"), let lproj = Bundle(path: path) {
            return lproj
        }
        return base
    }

    /// Chaîne de KEFKit dans une langue donnée. En français, la clé elle-même (aucune table
    /// n'est consultée : sinon `Bundle` choisirait une autre langue faute de table française).
    public static func string(_ value: String.LocalizationValue, language: String) -> String {
        guard language != developmentLanguage else {
            return String(localized: value, table: "Untranslated", bundle: .module)
        }
        return String(localized: value, bundle: bundle(for: language))
    }

    static let bundle = bundle(for: language)
}

extension String {
    /// Capitales selon la langue de l'interface (étiquettes « petites capitales » des designs).
    /// Sans effet sur les écritures sans casse (japonais).
    public var interfaceUppercased: String { uppercased(with: KEFLocalization.locale) }
}

/// Chaîne traduite de KEFKit dans la langue de l'interface (clé = texte français).
func localized(_ value: String.LocalizationValue) -> String {
    guard KEFLocalization.language != KEFLocalization.developmentLanguage else {
        return KEFLocalization.string(value, language: KEFLocalization.developmentLanguage)
    }
    return String(localized: value, bundle: KEFLocalization.bundle)
}
