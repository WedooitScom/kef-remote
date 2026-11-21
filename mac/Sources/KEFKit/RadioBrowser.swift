import Foundation

// Navigation dans l'arbre des radios airable (`getRows` paginé), indépendante de l'UI.
//
// Relevé sur une LS50 Wireless II : sous `…/airable/radios`, des conteneurs « Stations
// populaires » (`/popular`), « Tendance » (`/trending`), « Radios locales » (`/local`),
// « Haute qualité » (`/hq`), « Nouvelles stations » (`/new`) et « Filtre » (`/filter`) :
// - `/filter/origins` (régions → pays → villes), `/filter/languages`, `/filter/genres`
//   (genres → sous-genres) ;
// - une feuille de filtre (`…/filter\?g\=X`, `\?o\=`, `\?l\=`, combinables) liste d'abord
//   trois conteneurs de raffinement (`…/filter/origins\?g\=X`, `…/languages\?…`,
//   `…/genres\?…`), puis les stations (`…/id/airable/radio/<id>`).
// Toutes les rows sont des `container` ; les chemins (avec `\?` `\=` échappés) sont opaques.

/// Points d'entrée de l'explorateur.
public enum RadioDirectory: String, CaseIterable, Sendable, Hashable, Identifiable {
    case countries, genres, languages
    case popular, trending, local, highQuality, new

    public var id: String { rawValue }

    /// Chemin relatif à la racine des radios (`…/airable/radios/<chemin>`).
    public var relativePath: String {
        switch self {
        case .countries: "filter/origins"
        case .genres: "filter/genres"
        case .languages: "filter/languages"
        case .popular: "popular"
        case .trending: "trending"
        case .local: "local"
        case .highQuality: "hq"
        case .new: "new"
        }
    }

    public var title: String {
        switch self {
        case .countries: "Pays"
        case .genres: "Genres"
        case .languages: "Langues"
        case .popular: "Populaires"
        case .trending: "Tendance"
        case .local: "Locales"
        case .highQuality: "Haute qualité"
        case .new: "Nouvelles"
        }
    }

    public var subtitle: String {
        switch self {
        case .countries: "Par région et par pays"
        case .genres: "Jazz, rock, classique…"
        case .languages: "Stations par langue"
        case .popular: "Les plus écoutées"
        case .trending: "En ce moment"
        case .local: "Autour de l'enceinte"
        case .highQuality: "Haut débit"
        case .new: "Nouvelles stations"
        }
    }

    /// SF Symbol associé.
    public var symbol: String {
        switch self {
        case .countries: "globe.europe.africa.fill"
        case .genres: "guitars.fill"
        case .languages: "character.bubble.fill"
        case .popular: "flame.fill"
        case .trending: "chart.line.uptrend.xyaxis"
        case .local: "location.fill"
        case .highQuality: "waveform"
        case .new: "sparkles"
        }
    }

    /// Teinte (0…360) des tuiles.
    public var hue: Int {
        switch self {
        case .countries: 205
        case .genres: 18
        case .languages: 280
        case .popular: 8
        case .trending: 330
        case .local: 150
        case .highQuality: 45
        case .new: 255
        }
    }

    /// Les trois filtres (accueil de l'explorateur).
    public static let filters: [RadioDirectory] = [.countries, .genres, .languages]
    /// Les étagères de stations.
    public static let shelves: [RadioDirectory] = [.popular, .trending, .local, .highQuality, .new]

    /// Facette correspondante (filtres uniquement).
    public var facet: RadioFacet? {
        switch self {
        case .countries: .country
        case .genres: .genre
        case .languages: .language
        default: nil
        }
    }
}

/// Dimension d'un filtre airable.
public enum RadioFacet: String, Sendable, Hashable, CaseIterable {
    /// `origins` (régions, pays, villes).
    case country
    case language
    case genre

    /// Segment de chemin airable (`filter/<segment>`).
    public var pathSegment: String {
        switch self {
        case .country: "origins"
        case .language: "languages"
        case .genre: "genres"
        }
    }

    /// Libellé court (puce « affiner par… »).
    public var label: String {
        switch self {
        case .country: "Pays"
        case .language: "Langue"
        case .genre: "Genre"
        }
    }

    public var symbol: String {
        switch self {
        case .country: "globe"
        case .language: "character.bubble"
        case .genre: "music.note.list"
        }
    }
}

/// Où aller : un point d'entrée (racine propre à l'enceinte) ou un chemin airable renvoyé
/// tel quel par l'enceinte.
public enum RadioBrowseLocation: Sendable, Hashable {
    case directory(RadioDirectory)
    case path(String)
}

/// Une row d'une liste de l'explorateur.
public struct RadioBrowseItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// Station jouable (même format que les favoris).
        case station(Station)
        /// Sous-dossier (région, pays, genre, « Tout de : … », liste de stations…).
        case folder
        /// Conteneur de raffinement d'une liste filtrée (« Par localité », « Par langue »…).
        case refinement(RadioFacet)
    }

    public var id: String
    public var title: String
    public var path: String
    public var icon: String?
    public var kind: Kind

    public init(id: String, title: String, path: String, icon: String? = nil, kind: Kind) {
        self.id = id
        self.title = title
        self.path = path
        self.icon = icon
        self.kind = kind
    }

    public var station: Station? {
        if case .station(let s) = kind { return s }
        return nil
    }

    public var isFolder: Bool { kind == .folder }

    public var facet: RadioFacet? {
        if case .refinement(let f) = kind { return f }
        return nil
    }

    /// « Tout de: Europe » : toutes les stations du dossier parent.
    public var isAllOf: Bool {
        let t = title.lowercased()
        return t.hasPrefix("tout de") || t.hasPrefix("toutes de") || t.hasPrefix("all of")
    }

    /// Nom sans le préfixe « Tout de: » (« Europe »).
    public var displayTitle: String {
        guard isAllOf, let colon = title.firstIndex(of: ":") else { return title }
        let rest = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? title : rest
    }

    /// Valeur déjà appliquée d'un raffinement : « Langue: français » → « français ».
    public var activeValue: String? {
        guard facet != nil, let colon = title.firstIndex(of: ":") else { return nil }
        let rest = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}

/// Une page d'un conteneur airable (`getRows` de `offset` à `offset + rowCount - 1`).
public struct RadioBrowsePage: Sendable, Equatable {
    /// Chemin final (après `rowsRedirect`), à réutiliser pour les pages suivantes.
    public var path: String
    /// Titre de la liste (`roles.title`, « : » final retiré), s'il y en a un.
    public var title: String?
    /// Nombre total de rows (`rowsCount`), raffinements compris.
    public var totalCount: Int?
    public var offset: Int
    /// Rows brutes reçues (pour calculer la page suivante, même si certaines sont ignorées).
    public var rowCount: Int
    public var items: [RadioBrowseItem]

    public init(path: String, title: String? = nil, totalCount: Int? = nil, offset: Int = 0,
                rowCount: Int? = nil, items: [RadioBrowseItem]) {
        self.path = path
        self.title = title
        self.totalCount = totalCount
        self.offset = offset
        self.rowCount = rowCount ?? items.count
        self.items = items
    }

    /// Début de la page suivante.
    public var nextOffset: Int { offset + rowCount }

    /// Reste-t-il des rows après cette page ?
    public var hasMore: Bool {
        guard rowCount > 0 else { return false }
        if let totalCount { return nextOffset < totalCount }
        return false
    }
}

// MARK: - Analyse

extension KEFParser {
    static let demoStationPrefix = "demo:radio/"

    /// Facette d'un chemin de raffinement : `…/filter/<origins|languages|genres>\?…`.
    /// Un sous-dossier filtré (`…/filter/origins/<id>\?g\=…`) n'en est pas un.
    public static func refinementFacet(path: String) -> RadioFacet? {
        guard let range = path.range(of: "/filter/", options: .backwards) else { return nil }
        let tail = path[range.upperBound...]
        for facet in RadioFacet.allCases {
            let segment = facet.pathSegment
            if tail.hasPrefix(segment + "\\?") || tail.hasPrefix(segment + "?") { return facet }
        }
        return nil
    }

    /// Classe une row : station, raffinement ou dossier ; `nil` pour ce qui ne se parcourt
    /// pas (champ de formulaire, action, row sans chemin…).
    public static func browseItem(_ row: JSONValue) -> RadioBrowseItem? {
        guard let path = row["path"]?.nonEmptyString, let title = row["title"]?.nonEmptyString else { return nil }
        let type = row["type"]?.stringValue ?? "container"
        guard type == "container" || type == "audio" else { return nil }
        let icon = bestImage(row)
        if let station = normalizeStation(row) {
            return RadioBrowseItem(id: station.id, title: station.title, path: station.path, icon: station.icon,
                                   kind: .station(station))
        }
        // Un `audio` qui n'est pas une station airable (podcast…) : rien à parcourir.
        guard type == "container" else { return nil }
        if let facet = refinementFacet(path: path) {
            return RadioBrowseItem(id: path, title: title, path: path, icon: icon, kind: .refinement(facet))
        }
        return RadioBrowseItem(id: path, title: title, path: path, icon: icon, kind: .folder)
    }

    /// Titre d'en-tête : « Genre: » → « Genre », « Région: Europe » inchangé.
    public static func listTitle(_ raw: String?) -> String? {
        guard var t = raw?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        while t.hasSuffix(":") { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }
        return t.isEmpty ? nil : t
    }

    /// Page d'explorateur à partir d'une réponse `getRows`.
    public static func browsePage(_ response: JSONValue, path: String, offset: Int) -> RadioBrowsePage {
        let rows = response["rows"]?.arrayValue ?? []
        var seen = Set<String>()
        let items = rows.compactMap(browseItem).filter { seen.insert($0.id).inserted }
        return RadioBrowsePage(path: path, title: listTitle(response["roles"]?["title"]?.stringValue),
                               totalCount: response["rowsCount"]?.intValue, offset: offset,
                               rowCount: rows.count, items: items)
    }
}

// MARK: - Client

public extension SpeakerClient {
    /// Par défaut (faux clients des tests) : pas d'explorateur.
    func browseRadios(_ location: RadioBrowseLocation, from: Int, count: Int) async throws -> RadioBrowsePage {
        throw KEFError.invalidResponse("explorateur non disponible")
    }
}
