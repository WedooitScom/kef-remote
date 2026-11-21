import Foundation

// Arbre radio fictif du mode démo, aux mêmes formes que celui d'airable : étagères,
// filtres par localité / langue / genre (avec sous-niveaux), feuilles de filtre qui
// commencent par trois raffinements puis listent des stations, chemins avec `\?` `\=`
// échappés. Les stations du catalogue ont un genre, un pays et une langue : les
// combinaisons de filtres donnent des listes cohérentes.

extension DemoSpeakerClient {
    static let browseRoot = "demo:browse/radios"

    /// Nœud d'un arbre de filtre : `children == nil` = feuille (valeur de filtre).
    struct FilterNode: Sendable {
        let id: String
        let title: String
        var children: [FilterNode]?

        init(_ id: String, _ title: String, _ children: [FilterNode]? = nil) {
            self.id = id
            self.title = title
            self.children = children
        }

        /// Ce nœud et tous ses descendants.
        var allIDs: Set<String> {
            var ids: Set<String> = [id]
            for child in children ?? [] { ids.formUnion(child.allIDs) }
            return ids
        }

        func find(_ target: String) -> FilterNode? {
            if id == target { return self }
            for child in children ?? [] { if let found = child.find(target) { return found } }
            return nil
        }

        var leaves: [FilterNode] { children.map { $0.flatMap(\.leaves) } ?? [self] }
    }

    static let genreTree: [FilterNode] = [
        FilterNode("news", "Actualités", [FilterNode("news-info", "Info continue"), FilterNode("news-talk", "Débats")]),
        FilterNode("jazz", "Jazz", [FilterNode("bebop", "Bebop"), FilterNode("smooth", "Smooth Jazz"),
                                    FilterNode("vocal", "Vocal Jazz")]),
        FilterNode("rock", "Rock", [FilterNode("classic-rock", "Classic Rock"), FilterNode("metal", "Métal"),
                                    FilterNode("indie", "Rock indé")]),
        FilterNode("pop", "Pop"),
        FilterNode("classical", "Musique classique", [FilterNode("baroque", "Baroque"), FilterNode("opera", "Opéra"),
                                                      FilterNode("symphonic", "Symphonique")]),
        FilterNode("electro", "Electronic Dance", [FilterNode("house", "House"), FilterNode("techno", "Techno"),
                                                   FilterNode("ambient", "Ambient")]),
        FilterNode("hiphop", "Hip-Hop Rap"),
        FilterNode("reggae", "Reggae"),
        FilterNode("world", "Musiques du monde"),
        FilterNode("easy", "Easy listening"),
        FilterNode("oldies", "Oldies"),
        FilterNode("kids", "Enfants"),
        FilterNode("sport", "Sport"),
        FilterNode("musical", "Comédie musicale"),
        FilterNode("country", "Country"),
        FilterNode("folk", "Musique folk"),
    ]

    static let originTree: [FilterNode] = [
        FilterNode("africa", "Afrique", [FilterNode("sn", "Sénégal"), FilterNode("ma", "Maroc"), FilterNode("ci", "Côte d'Ivoire")]),
        FilterNode("namerica", "Amérique du Nord", [FilterNode("us", "États-Unis"), FilterNode("ca", "Canada"),
                                                     FilterNode("mx", "Mexique")]),
        FilterNode("samerica", "Amérique du Sud", [FilterNode("br", "Brésil"), FilterNode("ar", "Argentine")]),
        FilterNode("asia", "Asie", [FilterNode("jp", "Japon"), FilterNode("kr", "Corée du Sud"), FilterNode("in", "Inde")]),
        FilterNode("europe", "Europe", [
            FilterNode("de", "Allemagne"), FilterNode("be", "Belgique"), FilterNode("es", "Espagne"),
            FilterNode("fr", "France", [FilterNode("bordeaux", "Bordeaux"), FilterNode("lyon", "Lyon"),
                                        FilterNode("marseille", "Marseille"), FilterNode("paris", "Paris")]),
            FilterNode("ie", "Irlande"), FilterNode("it", "Italie"), FilterNode("nl", "Pays-Bas"),
            FilterNode("gb", "Royaume-Uni"), FilterNode("ch", "Suisse"),
        ]),
        FilterNode("oceania", "Océanie", [FilterNode("au", "Australie"), FilterNode("nz", "Nouvelle-Zélande")]),
    ]

    static let languageList: [FilterNode] = [
        FilterNode("fr", "français"), FilterNode("en", "anglais"), FilterNode("de", "allemand"),
        FilterNode("es", "espagnol"), FilterNode("it", "italien"), FilterNode("pt", "portugais"),
        FilterNode("nl", "néerlandais"), FilterNode("ja", "japonais"),
    ]

    /// Station du catalogue : genre (feuille), lieu (feuille) et langue.
    struct CatalogEntry: Sendable {
        let station: DemoStation
        let genre: String
        let origin: String
        let language: String
    }

    /// Ville ou pays → (nom court pour le titre, langue).
    static let placeInfo: [String: (name: String, language: String)] = [
        "paris": ("Paris", "fr"), "lyon": ("Lyon", "fr"), "marseille": ("Marseille", "fr"), "bordeaux": ("Bordeaux", "fr"),
        "de": ("Berlin", "de"), "gb": ("London", "en"), "it": ("Roma", "it"), "es": ("Madrid", "es"),
        "be": ("Bruxelles", "fr"), "ch": ("Genève", "fr"), "nl": ("Amsterdam", "nl"), "ie": ("Dublin", "en"),
        "us": ("New York", "en"), "ca": ("Montréal", "fr"), "mx": ("México", "es"), "br": ("Rio", "pt"),
        "ar": ("Buenos Aires", "es"), "sn": ("Dakar", "fr"), "ma": ("Casablanca", "fr"), "ci": ("Abidjan", "fr"),
        "jp": ("Tokyo", "ja"), "kr": ("Séoul", "en"), "in": ("Mumbai", "en"), "au": ("Sydney", "en"),
        "nz": ("Auckland", "en"),
    ]

    static let genreWords: [String: String] = [
        "news-info": "Info", "news-talk": "Débats", "bebop": "Bebop", "smooth": "Smooth", "vocal": "Jazz Voices",
        "classic-rock": "Classic Rock", "metal": "Metal", "indie": "Indie", "pop": "Pop", "baroque": "Baroque",
        "opera": "Opéra", "symphonic": "Symphonie", "house": "House", "techno": "Techno", "ambient": "Ambient",
        "hiphop": "Hip-Hop", "reggae": "Reggae", "world": "World", "easy": "Easy", "oldies": "Oldies",
        "kids": "Kids", "sport": "Sport", "musical": "Broadway", "country": "Country", "folk": "Folk",
    ]

    /// Catalogue : les neuf stations de démo historiques, puis des stations générées
    /// (déterministes : mêmes noms à chaque lancement).
    static let catalog: [CatalogEntry] = {
        var entries: [CatalogEntry] = []
        let base: [(Int, String, String, String)] = [
            (1, "vocal", "paris", "fr"), (2, "pop", "lyon", "fr"), (3, "house", "de", "de"),
            (4, "symphonic", "paris", "fr"), (5, "news-info", "paris", "fr"), (6, "metal", "gb", "en"),
            (7, "easy", "marseille", "fr"), (8, "smooth", "bordeaux", "fr"), (9, "world", "es", "es"),
        ]
        for (n, genre, origin, language) in base {
            guard let s = stations.first(where: { $0.n == n }) else { continue }
            entries.append(CatalogEntry(station: s, genre: genre, origin: origin, language: language))
        }
        // Pondérations : beaucoup de France et d'Europe, de pop, de jazz et de rock.
        let places = ["paris", "paris", "paris", "lyon", "lyon", "marseille", "bordeaux", "de", "de", "gb", "gb",
                      "it", "es", "be", "ch", "nl", "ie", "us", "us", "ca", "mx", "br", "ar", "sn", "ma", "ci",
                      "jp", "kr", "in", "au", "nz"]
        let genres = ["pop", "pop", "pop", "bebop", "smooth", "smooth", "vocal", "classic-rock", "classic-rock", "metal",
                      "indie", "news-info", "news-talk", "baroque", "opera", "symphonic", "house", "house", "techno",
                      "ambient", "hiphop", "hiphop", "reggae", "world", "easy", "oldies", "oldies", "kids", "sport",
                      "musical", "country", "folk"]
        let suffixes = ["FM", "Radio", "Live", "Club", "24", "Express", "Hits", "One", "Nights", "Station", "Wave", "Café"]
        var seed: UInt64 = 0x4B45_4652 // « KEFR »
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        var titles = Set(entries.map(\.station.title))
        for i in 0..<240 {
            let origin = places[next(places.count)]
            let genre = genres[next(genres.count)]
            let place = placeInfo[origin] ?? ("Radio", "fr")
            var title = "\(place.name) \(genreWords[genre] ?? "Radio") \(suffixes[next(suffixes.count)])"
            if !titles.insert(title).inserted {
                title += " \(i % 9 + 2)"
                titles.insert(title)
            }
            let genreTitle = genreTree.lazy.compactMap { $0.find(genre) }.first?.title ?? ""
            let placeTitle = originTree.lazy.compactMap { $0.find(origin) }.first?.title ?? ""
            let hue = (RadioCatalog.genreStyle(for: genreTitle).hue + next(40) - 20 + 360) % 360
            let station = DemoStation(n: 100 + i, title: title, desc: "\(genreTitle) · \(placeTitle)", hue: hue,
                                      now: "En direct de \(place.name)")
            // Ici une langue sur six diffère de celle du lieu (émissions en anglais…).
            let language = next(6) == 0 ? "en" : place.language
            entries.append(CatalogEntry(station: station, genre: genre, origin: origin, language: language))
        }
        return entries
    }()

    /// Station de démo par numéro (historiques et catalogue).
    static func demoStation(_ n: Int) -> DemoStation? {
        stations.first(where: { $0.n == n }) ?? catalog.first(where: { $0.station.n == n })?.station
    }

    // MARK: Chemins

    /// `filter\?g\=jazz&o\=fr` → `["g": "jazz", "o": "fr"]`.
    static func parseQuery(_ query: Substring) -> [String: String] {
        var params: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.components(separatedBy: "\\=")
            if parts.count == 2 { params[parts[0]] = parts[1] }
        }
        return params
    }

    static func encodeQuery(_ params: [String: String]) -> String {
        guard !params.isEmpty else { return "" }
        // Ordre fixe (g, l, o), comme airable.
        return "\\?" + params.sorted { $0.key < $1.key }.map { "\($0.key)\\=\($0.value)" }.joined(separator: "&")
    }

    static func leafPath(_ params: [String: String]) -> String { "\(browseRoot)/filter\(encodeQuery(params))" }

    static func facetKey(_ facet: RadioFacet) -> String {
        switch facet {
        case .country: "o"
        case .language: "l"
        case .genre: "g"
        }
    }

    static func tree(_ facet: RadioFacet) -> [FilterNode] {
        switch facet {
        case .country: originTree
        case .language: languageList
        case .genre: genreTree
        }
    }

    static func node(_ facet: RadioFacet, _ id: String?) -> FilterNode? {
        guard let id else { return nil }
        return tree(facet).lazy.compactMap { $0.find(id) }.first
    }

    // MARK: Rows

    static func stationRow(_ s: DemoStation) -> JSONValue {
        let station = Self.station(s)
        return ["type": "container", "title": .string(s.title), "path": .string(station.path), "id": .string(station.id),
                "icon": .string(station.icon ?? ""), "description": .string(s.desc), "containerPlayable": true,
                "mediaData": ["metaData": ["serviceID": .string(KEFParser.airableService)]]]
    }

    static func containerRow(_ title: String, _ path: String) -> JSONValue {
        ["type": "container", "title": .string(title), "path": .string(path), "containerType": "none"]
    }

    /// Stations d'une feuille de filtre.
    static func matching(_ params: [String: String]) -> [CatalogEntry] {
        let genres = node(.genre, params["g"])?.allIDs
        let origins = node(.country, params["o"])?.allIDs
        let language = params["l"]
        return catalog.filter { entry in
            (genres?.contains(entry.genre) ?? true) && (origins?.contains(entry.origin) ?? true)
                && (language.map { $0 == entry.language } ?? true)
        }
    }

    /// Étagères : sélections déterministes du catalogue.
    static func shelf(_ name: String) -> [CatalogEntry]? {
        switch name {
        case "popular": return Array(catalog.prefix(9)) + catalog.dropFirst(9).enumerated().filter { $0.offset % 3 == 0 }.map(\.element).prefix(63)
        case "trending": return catalog.enumerated().filter { $0.offset % 7 == 2 }.map(\.element).prefix(24).map { $0 }
        case "local":
            let france = node(.country, "fr")?.allIDs ?? []
            return catalog.filter { france.contains($0.origin) }.prefix(40).map { $0 }
        case "hq":
            let hq = (node(.genre, "classical")?.allIDs ?? []).union(node(.genre, "jazz")?.allIDs ?? [])
                .union(node(.genre, "electro")?.allIDs ?? [])
            return catalog.filter { hq.contains($0.genre) }.prefix(30).map { $0 }
        case "new": return Array(catalog.suffix(18).reversed())
        default: return nil
        }
    }

    /// Réponse `getRows` complète (avant pagination) d'un chemin démo, sinon `nil`.
    static func browseResponse(_ path: String) -> (title: String, rows: [JSONValue])? {
        guard path.hasPrefix(browseRoot) else { return nil }
        var rest = Substring(path.dropFirst(browseRoot.count))
        if rest.hasPrefix("/") { rest = rest.dropFirst() }
        let base: Substring
        var params: [String: String] = [:]
        if let range = rest.range(of: "\\?") {
            base = rest[..<range.lowerBound]
            params = parseQuery(rest[range.upperBound...])
        } else {
            base = rest
        }
        let parts = base.split(separator: "/").map(String.init)

        if parts.isEmpty {
            let shelves = [("Stations populaires", "popular"), ("Tendance", "trending"), ("Radios locales", "local"),
                           ("Haute qualité", "hq"), ("Nouvelles stations", "new"), ("Filtre", "filter")]
            return ("Radios", shelves.map { containerRow($0.0, "\(browseRoot)/\($0.1)") })
        }
        if parts.count == 1, let entries = shelf(parts[0]) {
            let titles = ["popular": "Stations populaires", "trending": "Tendance", "local": "Radios locales",
                          "hq": "Haute qualité", "new": "Nouvelles stations"]
            return (titles[parts[0]] ?? "Radios", entries.map { stationRow($0.station) })
        }
        guard parts[0] == "filter" else { return nil }

        if parts.count == 1 {
            if params.isEmpty {
                return ("Filtre", [containerRow("Par localité", "\(browseRoot)/filter/origins"),
                                   containerRow("Par langue", "\(browseRoot)/filter/languages"),
                                   containerRow("Par genre", "\(browseRoot)/filter/genres")])
            }
            // Feuille : trois raffinements, puis les stations.
            let query = encodeQuery(params)
            func refinement(_ facet: RadioFacet, _ unset: String, _ set: String) -> JSONValue {
                let title = node(facet, params[facetKey(facet)]).map { "\(set): \($0.title)" } ?? unset
                return containerRow(title, "\(browseRoot)/filter/\(facet.pathSegment)\(query)")
            }
            let refinements = [refinement(.country, "Par localité", "Localité"),
                               refinement(.language, "Par langue", "Langue"),
                               refinement(.genre, "Par genre", "Genre")]
            return ("Filtre", refinements + matching(params).map { stationRow($0.station) })
        }

        // Liste de valeurs d'un filtre (éventuellement sous un nœud, éventuellement déjà filtrée).
        guard let facet = RadioFacet.allCases.first(where: { $0.pathSegment == parts[1] }) else { return nil }
        let key = facetKey(facet)
        let parent = parts.count > 2 ? node(facet, parts[2]) : nil
        if parts.count > 2 && parent == nil { return nil }
        let children = parent?.children ?? tree(facet)
        let query = encodeQuery(params.filter { $0.key != key })
        var rows: [JSONValue] = []
        if let parent {
            var all = params
            all[key] = parent.id
            rows.append(containerRow("Tout de: \(parent.title)", leafPath(all)))
        }
        for child in children {
            if child.children != nil {
                rows.append(containerRow(child.title, "\(browseRoot)/filter/\(facet.pathSegment)/\(child.id)\(query)"))
            } else {
                var leaf = params
                leaf[key] = child.id
                rows.append(containerRow(child.title, leafPath(leaf)))
            }
        }
        let heading: String
        switch facet {
        case .country: heading = parent.map { "Région: \($0.title)" } ?? "Région"
        case .language: heading = "Langue"
        case .genre: heading = parent.map { "Genre: \($0.title)" } ?? "Genre: "
        }
        return (heading, rows)
    }
}
