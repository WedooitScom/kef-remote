import AppKit
import KEFKit

/// Langue de l'interface (Réglages › Langue). « Système » suit la langue du Mac ; un choix
/// explicite est enregistré dans `AppleLanguages` du domaine de l'app (comme le fait
/// Réglages Système › Langue et région › Applications) et prend effet au lancement suivant.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, fr, en, es, it, ja

    var id: String { rawValue }

    static let defaultsKey = "AppleLanguages"

    /// Nom affiché : chaque langue dans sa propre langue, « Système » dans la langue courante.
    var label: String {
        switch self {
        case .system: String(localized: "Système")
        case .fr: "Français"
        case .en: "English"
        case .es: "Español"
        case .it: "Italiano"
        case .ja: "日本語"
        }
    }

    /// Choix enregistré pour l'app (sans la préférence globale du Mac).
    static var stored: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: domainName)
        guard let first = (domain?[defaultsKey] as? [String])?.first else { return .system }
        let code = Locale.Language(identifier: first).languageCode?.identifier ?? first
        return AppLanguage(rawValue: code) ?? .system
    }

    static func store(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: defaultsKey)
        }
    }

    /// Langue que l'app prendra au prochain lancement avec ce choix.
    var effectiveLanguage: String {
        guard self == .system else { return rawValue }
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let preferences = global?[Self.defaultsKey] as? [String] ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: KEFLocalization.supportedLanguages, forPreferences: preferences).first
            ?? KEFLocalization.developmentLanguage
    }

    private static var domainName: String {
        Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    }

    // MARK: Lancement

    /// `--language <code>` (captures) : impose la langue pour ce lancement seulement, sans
    /// rien enregistrer. À appeler avant le premier accès aux chaînes traduites.
    static func applyLaunchOverride(arguments: [String] = CommandLine.arguments) {
        guard let i = arguments.firstIndex(of: "--language"), arguments.indices.contains(i + 1) else { return }
        let code = arguments[i + 1]
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        domain[defaultsKey] = [code]
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    /// Relance possible : uniquement depuis le bundle `.app`.
    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Relance l'app (nouvelle instance, mêmes options hors langue), puis quitte celle-ci.
    @MainActor
    static func relaunch() {
        var arguments: [String] = []
        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            if argument == "--language" || argument == "-\(defaultsKey)" { _ = iterator.next(); continue }
            arguments.append(argument)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
