import Foundation

/// Habillage de l'explorateur : drapeau d'un pays, pictogramme et couleur d'un genre,
/// globe d'une région, code d'une langue. Tout se déduit des noms (en français) renvoyés
/// par airable, avec un repli générique quand rien ne correspond.
public enum RadioCatalog {
    // MARK: Normalisation

    /// Minuscules, sans accents ni ponctuation de liaison : « Île-de-Man » → « ile de man ».
    public static func fold(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
        let spaced = folded.map { "-_/.,()".contains($0) ? " " : $0 }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    // MARK: Pays

    /// Noms airable qui diffèrent de ceux de `Locale` (fr_FR).
    static let countryAliases: [String: String] = [
        "macedoine": "MK", "macedoine du nord": "MK", "vatican": "VA", "kosovo": "XK",
        "bielorussie": "BY", "republique tcheque": "CZ", "tchequie": "CZ", "coree du sud": "KR",
        "coree du nord": "KP", "etats unis d'amerique": "US", "usa": "US", "birmanie": "MM",
        "swaziland": "SZ", "republique democratique du congo": "CD", "congo kinshasa": "CD",
        "congo brazzaville": "CG", "cote d'ivoire": "CI", "hong kong": "HK", "macao": "MO",
        "palestine": "PS", "taiwan": "TW", "iles vierges americaines": "VI", "angleterre": "GB",
        "ecosse": "GB", "pays de galles": "GB", "irlande du nord": "GB",
    ]

    /// Nom français (replié) → code ISO 3166 à deux lettres.
    static let countryCodes: [String: String] = {
        let fr = Locale(identifier: "fr_FR")
        var table: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, code.allSatisfy(\.isLetter),
                  let name = fr.localizedString(forRegionCode: code) else { continue }
            table[fold(name)] = code
        }
        for (name, code) in countryAliases { table[name] = code }
        return table
    }()

    /// Code ISO d'un pays d'après son nom français (« Allemagne » → « DE »), sinon `nil`.
    public static func regionCode(forCountry name: String) -> String? {
        let key = fold(name)
        guard !key.isEmpty else { return nil }
        if let code = countryCodes[key] { return code }
        // « Saint-Marin (république) », « France métropolitaine »… : premier mot significatif.
        if let paren = name.firstIndex(of: "("), let code = countryCodes[fold(String(name[..<paren]))] { return code }
        return nil
    }

    /// Drapeau emoji d'un code ISO (« FR » → 🇫🇷).
    public static func flag(regionCode code: String) -> String? {
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return nil }
        var flag = ""
        for scalar in letters {
            guard let indicator = Unicode.Scalar(0x1F1E6 + scalar.value - 65) else { return nil }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }

    /// Drapeau d'un pays d'après son nom français, sinon `nil` (repli : globe).
    public static func flag(forCountry name: String) -> String? {
        regionCode(forCountry: name).flatMap { flag(regionCode: $0) }
    }

    /// Globe adapté à une région du monde (« Europe », « Amérique du Sud »…), sinon `nil`.
    public static func regionSymbol(forName name: String) -> String? {
        let key = fold(name)
        if key.contains("amerique") || key.contains("caraibe") { return "globe.americas.fill" }
        if key.contains("asie") || key.contains("oceanie") || key.contains("pacifique") { return "globe.asia.australia.fill" }
        if key.contains("europe") || key.contains("afrique") || key.contains("moyen orient") { return "globe.europe.africa.fill" }
        return nil
    }

    // MARK: Langues

    /// Nom français (replié) → code de langue ISO 639 (« français » → « fr »).
    static let languageCodes: [String: String] = {
        let fr = Locale(identifier: "fr_FR")
        var table: [String: String] = [:]
        // Les codes à deux lettres d'abord : ils l'emportent sur les variantes à trois lettres.
        let codes = Locale.LanguageCode.isoLanguageCodes.map(\.identifier).sorted { $0.count > $1.count }
        for code in codes {
            guard let name = fr.localizedString(forLanguageCode: code) else { continue }
            table[fold(name)] = code
        }
        return table
    }()

    /// Code court d'une langue pour une pastille (« français » → « FR »), sinon `nil`.
    public static func languageBadge(forName name: String) -> String? {
        languageCodes[fold(name)].map { $0.uppercased() }
    }

    // MARK: Genres

    /// Pictogramme (SF Symbol) et teinte (0…360) d'un genre.
    public struct GenreStyle: Sendable, Equatable {
        public var symbol: String
        public var hue: Int
        /// Vrai si le genre a été reconnu (sinon repli générique).
        public var matched: Bool
    }

    /// Mots-clés (repliés) → style. L'ordre compte : « Comédie musicale » avant « comédie »,
    /// « Jazz Pop » côté jazz, « Hip-Hop » avant « pop ».
    static let genreRules: [(keywords: [String], symbol: String, hue: Int)] = [
        (["actualite", "info", "news", "debat", "talk", "parole"], "newspaper.fill", 212),
        (["sport"], "sportscourt.fill", 122),
        (["jazz", "bebop", "bepop", "swing", "blues"], "music.quarternote.3", 32),
        (["classique", "classical", "baroque", "opera", "symphon"], "pianokeys", 46),
        (["comedie musicale", "musical", "bande son", "soundtrack", "film", "cinema"], "film.fill", 345),
        (["hip hop", "rap", "r&b", "rnb"], "headphones", 285),
        (["urbain", "urban"], "building.2.fill", 298),
        (["rock", "metal", "punk", "grunge"], "guitars.fill", 4),
        (["club 40", "top 40", "top 50", "charts"], "music.mic", 322),
        (["electro", "dance", "house", "techno", "trance", "edm", "club"], "waveform", 262),
        (["pop", "hits", "variete", "chanson"], "music.mic", 322),
        (["reggae", "ska", "dub"], "sun.max.fill", 92),
        (["country", "western", "bluegrass"], "music.note.house.fill", 26),
        (["folk", "acoustique"], "leaf.fill", 78),
        (["monde", "world", "tradition", "latin", "afric"], "globe.americas.fill", 172),
        (["enfant", "kids", "jeunesse"], "teddybear.fill", 54),
        (["religi", "gospel", "chretien", "spiritu", "louange"], "sparkles", 250),
        (["education", "college", "universit", "etudiant"], "graduationcap.fill", 228),
        (["oldies", "retro", "nostalgi", "decennie", "annees"], "clock.arrow.circlepath", 18),
        (["easy listening", "lounge", "chill", "ambient", "relax", "detente"], "cup.and.saucer.fill", 188),
        (["divertissement", "comedie", "humour", "entertainment"], "theatermasks.fill", 305),
        (["public", "communaut", "associati"], "person.3.fill", 140),
        (["saison", "noel", "christmas", "fete"], "snowflake", 198),
        (["freeform", "eclectique", "eclectic", "alternati"], "shuffle", 160),
        (["soul", "funk", "disco", "groove"], "music.quarternote.3", 12),
    ]

    /// Style d'un genre d'après son nom, avec repli (« music.note », teinte stable dérivée du nom).
    public static func genreStyle(for name: String) -> GenreStyle {
        let key = fold(name)
        for rule in genreRules where rule.keywords.contains(where: { key.contains($0) }) {
            return GenreStyle(symbol: rule.symbol, hue: rule.hue, matched: true)
        }
        return GenreStyle(symbol: "music.note", hue: stableHue(key), matched: false)
    }

    /// Teinte déterministe (même nom → même couleur d'un lancement à l'autre).
    public static func stableHue(_ s: String) -> Int {
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % 360)
    }

    /// Tous les pictogrammes utilisés (vérifiés par les tests).
    public static var allSymbols: [String] {
        Array(Set(genreRules.map(\.symbol) + ["music.note", "globe.americas.fill", "globe.asia.australia.fill",
                                               "globe.europe.africa.fill", "globe"]
            + RadioDirectory.allCases.map(\.symbol) + RadioFacet.allCases.map(\.symbol))).sorted()
    }
}
