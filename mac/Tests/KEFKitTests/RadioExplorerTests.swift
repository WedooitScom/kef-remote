import AppKit
import Foundation
import Testing
@testable import KEFKit

@Suite("Explorateur : analyse des rows")
struct RadioBrowseParserTests {
    static let root = "airable:https://1234567890.airable.io/airable/radios"

    @Test func genresAreFoldersOrLeaves() throws {
        let page = KEFParser.browsePage(try fixture("browse-genres"), path: Self.root + "/filter/genres", offset: 0)
        #expect(page.totalCount == 28)
        #expect(page.items.count == 28)
        #expect(page.title == "Genre") // « Genre: » nettoyé
        #expect(page.items.allSatisfy { $0.isFolder })
        let jazz = try #require(page.items.first { $0.title == "Jazz" })
        #expect(jazz.path.hasSuffix("filter/genres/5755660091526807"))
        let oldies = try #require(page.items.first { $0.title == "Oldies" })
        #expect(oldies.path.hasSuffix(#"filter\?g\=5797228447161615"#))
        #expect(!page.hasMore)
    }

    @Test func leafSplitsRefinementsAndStations() throws {
        let response = try fixture("browse-leaf")
        let path = Self.root + #"/filter\?g\=5797228447161615"#
        let page = KEFParser.browsePage(response, path: path, offset: 0)
        #expect(page.totalCount == 3171)
        #expect(page.title == "Filtre")
        let refinements = page.items.compactMap(\.facet)
        #expect(refinements == [.country, .language, .genre])
        let stations = page.items.compactMap(\.station)
        #expect(stations.count == 5)
        #expect(stations.allSatisfy { $0.path.contains(KEFParser.stationMarker) && $0.icon != nil })
        #expect(page.rowCount == 8)
        #expect(page.nextOffset == 8)
        #expect(page.hasMore)
    }

    @Test func regionHasAllOfAndCountries() throws {
        let page = KEFParser.browsePage(try fixture("browse-europe"), path: Self.root + "/filter/origins/6367601698730142", offset: 0)
        #expect(page.title == "Région: Europe")
        let first = try #require(page.items.first)
        #expect(first.isAllOf)
        #expect(first.displayTitle == "Europe")
        #expect(first.isFolder)
        #expect(page.items.dropFirst().allSatisfy { !$0.isAllOf && $0.isFolder })
    }

    @Test func filterRootIsNotRefinement() throws {
        let page = KEFParser.browsePage(try fixture("browse-filter"), path: Self.root + "/filter", offset: 0)
        // `filter/origins` sans `\?` : point d'entrée, pas un raffinement.
        #expect(page.items.map(\.title) == ["Par localité", "Par langue", "Par genre"])
        #expect(page.items.allSatisfy { $0.isFolder })
    }

    @Test func classification() {
        let r = Self.root
        #expect(KEFParser.refinementFacet(path: r + #"/filter/origins\?g\=1"#) == .country)
        #expect(KEFParser.refinementFacet(path: r + #"/filter/languages\?l\=3"#) == .language)
        #expect(KEFParser.refinementFacet(path: r + #"/filter/genres\?g\=1&o\=2"#) == .genre)
        // Sous-dossier filtré (région d'un raffinement) : dossier.
        #expect(KEFParser.refinementFacet(path: r + #"/filter/origins/2680\?g\=1"#) == nil)
        #expect(KEFParser.refinementFacet(path: r + "/filter/genres") == nil)
        #expect(KEFParser.refinementFacet(path: r + #"/filter\?g\=1"#) == nil)
        // Formulaire / action : ignorés.
        #expect(KEFParser.browseItem(["type": "value", "title": "q", "path": "airable:form7:q"]) == nil)
        let active = KEFParser.browseItem(["type": "container", "title": "Langue: français",
                                           "path": .string(r + #"/filter/languages\?l\=3"#)])
        #expect(active?.facet == .language)
        #expect(active?.activeValue == "français")
        #expect(KEFParser.listTitle("Genre: ") == "Genre")
        #expect(KEFParser.listTitle("  ") == nil)
    }

    @Test func paginationAndRedirect() async throws {
        let link = try fixtureData("radios-link")
        let genres = try fixtureData("browse-genres")
        let leaf = try fixtureData("browse-leaf")
        let leafPath = Self.root + #"/filter\?g\=5797228447161615"#
        let session = MockURLProtocol.session(id: "browse") { req in
            switch req.query("path") {
            case "airable:linkService_airable.radios": return (200, link)
            case Self.root: return (200, Data(#"{"rowsCount":0,"rows":[]}"#.utf8))
            case Self.root + "/filter/genres": return (200, genres)
            case "airable:redirect-me": return (200, Data(#"{"rows":[],"rowsRedirect":"\#(leafPath.replacingOccurrences(of: "\\", with: "\\\\"))"}"#.utf8))
            case leafPath: return (200, leaf)
            default: return (404, Data())
            }
        }
        let client = KEFHTTPClient(host: "192.0.2.1", session: session)
        let page = try await client.browseRadios(.directory(.genres), from: 0, count: 50)
        #expect(page.items.count == 28)
        let redirected = try await client.browseRadios(.path("airable:redirect-me"), from: 50, count: 50)
        #expect(redirected.path == leafPath) // pages suivantes : chemin final
        #expect(redirected.offset == 50)
        let requests = MockURLProtocol.requests(id: "browse")
        let last = try #require(requests.last)
        #expect(last.query("path") == leafPath) // chemin opaque renvoyé tel quel
        #expect(last.query("from") == "50")
        #expect(last.query("to") == "99") // `to` inclusif
        await #expect(throws: KEFError.self) { try await client.browseRadios(.path("demo:browse/radios"), from: 0, count: 5) }
    }
}

@Suite("Explorateur : habillage")
struct RadioCatalogTests {
    @Test func flags() {
        #expect(RadioCatalog.flag(forCountry: "France") == "🇫🇷")
        #expect(RadioCatalog.flag(forCountry: "Allemagne") == "🇩🇪")
        #expect(RadioCatalog.flag(forCountry: "Royaume-Uni") == "🇬🇧")
        #expect(RadioCatalog.flag(forCountry: "République tchèque") == "🇨🇿")
        #expect(RadioCatalog.flag(forCountry: "Macédoine") == "🇲🇰")
        #expect(RadioCatalog.flag(forCountry: "Île de Man") == "🇮🇲")
        #expect(RadioCatalog.flag(forCountry: "États-Unis") == "🇺🇸")
        #expect(RadioCatalog.flag(forCountry: "Europe") == nil)
        #expect(RadioCatalog.flag(forCountry: "Aix-en-Provence") == nil)
        #expect(RadioCatalog.regionSymbol(forName: "Amérique du Sud") == "globe.americas.fill")
        #expect(RadioCatalog.regionSymbol(forName: "Océanie") == "globe.asia.australia.fill")
        #expect(RadioCatalog.flag(regionCode: "x1") == nil)
    }

    @Test func languages() {
        #expect(RadioCatalog.languageBadge(forName: "français") == "FR")
        #expect(RadioCatalog.languageBadge(forName: "allemand") == "DE")
        #expect(RadioCatalog.languageBadge(forName: "langue imaginaire") == nil)
    }

    @Test func genreIcons() {
        #expect(RadioCatalog.genreStyle(for: "Jazz").symbol == "music.quarternote.3")
        #expect(RadioCatalog.genreStyle(for: "Jazz Pop").symbol == "music.quarternote.3")
        #expect(RadioCatalog.genreStyle(for: "Musique classique").symbol == "pianokeys")
        #expect(RadioCatalog.genreStyle(for: "Rock").symbol == "guitars.fill")
        #expect(RadioCatalog.genreStyle(for: "Hip-Hop Rap").symbol == "headphones")
        #expect(RadioCatalog.genreStyle(for: "Comédie musicale").symbol == "film.fill")
        #expect(RadioCatalog.genreStyle(for: "Actualités").symbol == "newspaper.fill")
        let unknown = RadioCatalog.genreStyle(for: "Zouk-Kompa")
        #expect(!unknown.matched && unknown.symbol == "music.note")
        #expect(unknown.hue == RadioCatalog.genreStyle(for: "Zouk-Kompa").hue) // stable
    }

    @Test func everyGenreOfTheSpeakerHasAStyle() throws {
        let page = KEFParser.browsePage(try fixture("browse-genres"), path: "x", offset: 0)
        let unmatched = page.items.filter { !RadioCatalog.genreStyle(for: $0.title).matched }.map(\.title)
        #expect(unmatched.isEmpty, "genres sans pictogramme : \(unmatched)")
    }

    @Test func symbolsExist() {
        for symbol in RadioCatalog.allSymbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "SF Symbol absent : \(symbol)")
        }
    }
}

@MainActor
@Suite("Explorateur : navigation et arbre démo")
struct RadioExplorerModelTests {
    func makeModel() -> (RadioExplorerModel, DemoSpeakerClient) {
        let demo = DemoSpeakerClient(latency: .zero)
        let model = RadioExplorerModel { location, from, count in
            try await demo.browseRadios(location, from: from, count: count)
        }
        return (model, demo)
    }

    @Test func stackNavigation() async throws {
        let (explorer, _) = makeModel()
        #expect(explorer.isHome)
        let genres = explorer.open(.genres)
        await explorer.waitUntilLoaded(genres)
        #expect(genres.state == .loaded)
        #expect(genres.style == .genres)
        let jazz = try #require(genres.items.first { $0.title == "Jazz" })
        let jazzPage = try #require(explorer.open(jazz))
        await explorer.waitUntilLoaded(jazzPage)
        #expect(explorer.stack.count == 2)
        #expect(jazzPage.style == .genres) // sous-genres : tuiles
        let all = try #require(jazzPage.items.first)
        #expect(all.isAllOf && all.displayTitle == "Jazz")
        let leaf = try #require(explorer.open(all))
        await explorer.waitUntilLoaded(leaf)
        #expect(leaf.style == .stations)
        // Fil d'Ariane sans doublon (« Genres › Jazz › Toutes les stations »), en-tête « Jazz ».
        #expect(explorer.stack.map(\.title) == ["Genres", "Jazz", RadioExplorerModel.allStationsTitle])
        #expect(leaf.headerTitle == "Jazz")
        #expect(leaf.scope == "Jazz")
        #expect(jazzPage.headerTitle == "Jazz" && jazzPage.scope == nil)
        #expect(leaf.refinements.map(\.facet) == [.country, .language, .genre])
        #expect(leaf.refinements.last?.activeValue == "Jazz")
        #expect(!leaf.stations.isEmpty)
        #expect(leaf.items.allSatisfy { $0.station != nil })

        // Raffinement : Jazz → par localité → Europe → France.
        let byCountry = try #require(explorer.open(leaf.refinements[0]))
        await explorer.waitUntilLoaded(byCountry)
        #expect(byCountry.style == .countries)
        #expect(byCountry.title == "Pays")
        let europe = try #require(byCountry.items.first { $0.title == "Europe" })
        let europePage = try #require(explorer.open(europe))
        await explorer.waitUntilLoaded(europePage)
        let france = try #require(europePage.items.first { $0.title == "France" })
        #expect(RadioCatalog.flag(forCountry: france.title) == "🇫🇷")
        #expect(explorer.open(leaf.stations.map { RadioBrowseItem(id: $0.id, title: $0.title, path: $0.path, kind: .station($0)) }[0]) == nil)

        explorer.pop(to: jazzPage)
        #expect(explorer.current === jazzPage)
        explorer.pop()
        #expect(explorer.current === genres)
        explorer.pop(to: nil)
        #expect(explorer.isHome)
    }

    @Test func pagingLoadsFiftyAtATime() async throws {
        let (explorer, _) = makeModel()
        let popular = explorer.open(.popular)
        await explorer.waitUntilLoaded(popular)
        #expect(popular.items.count == RadioExplorerModel.pageSize)
        #expect(popular.hasMore)
        let total = try #require(popular.totalCount)
        explorer.loadMore(popular)
        await explorer.waitUntilLoaded(popular)
        #expect(popular.items.count == total)
        #expect(!popular.hasMore)
        explorer.loadMore(popular) // sans effet
        #expect(popular.state == .loaded)

        popular.filterText = "radio cuivre"
        #expect(popular.filteredItems.map(\.title) == ["Radio Cuivre", "Radio Cuivre Groove"])
    }

    @Test func combinedFiltersAreCoherent() async throws {
        let (explorer, demo) = makeModel()
        let page = try await demo.browseRadios(.path(DemoSpeakerClient.leafPath(["g": "jazz", "o": "fr"])), from: 0, count: 500)
        let stations = page.items.compactMap(\.station)
        #expect(!stations.isEmpty)
        let jazz = DemoSpeakerClient.node(.genre, "jazz")!.allIDs
        let france = DemoSpeakerClient.node(.country, "fr")!.allIDs
        for station in stations {
            let entry = try #require(DemoSpeakerClient.catalog.first { DemoSpeakerClient.station($0.station).id == station.id })
            #expect(jazz.contains(entry.genre) && france.contains(entry.origin))
        }
        // Chaque feuille d'un point d'entrée s'ouvre sans erreur.
        for directory in RadioDirectory.allCases {
            let p = explorer.open(directory)
            await explorer.waitUntilLoaded(p)
            #expect(p.state == .loaded, "\(directory)")
            #expect(!p.items.isEmpty, "\(directory)")
        }
    }

    @Test func errorThenRetry() async throws {
        let failing = FailOnce()
        let explorer = RadioExplorerModel { location, from, count in
            try await failing.load(location, from: from, count: count)
        }
        let page = explorer.open(.genres)
        await explorer.waitUntilLoaded(page)
        guard case .failed = page.state else { Issue.record("échec attendu : \(page.state)"); return }
        explorer.retry(page)
        await explorer.waitUntilLoaded(page)
        #expect(page.state == .loaded)
        #expect(!page.items.isEmpty)
    }

    @Test func demoStationsFromExplorerPlayAndBecomeFavorites() async throws {
        let (explorer, demo) = makeModel()
        let page = explorer.open(.new)
        await explorer.waitUntilLoaded(page)
        let station = try #require(page.stations.first)
        let played = try await demo.playStation(path: station.path)
        #expect(played.isSameStation(as: station))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kef-explorer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let favorites = FavoritesStore(fileURL: dir.appendingPathComponent("favorites.json"))
        #expect(!favorites.contains(station))
        #expect(favorites.add(station))
        #expect(favorites.contains(station))
        // Relu depuis le disque : même station (chemin opaque conservé).
        let reloaded = FavoritesStore(fileURL: favorites.fileURL)
        #expect(reloaded.items.first?.path == station.path)
        favorites.toggle(station)
        #expect(!favorites.contains(station))
    }

    @Test func resetReturnsHome() async throws {
        let (explorer, _) = makeModel()
        explorer.loadShelves()
        #expect(explorer.shelves.count == 2)
        let page = explorer.open(.popular)
        #expect(page === explorer.shelves[.popular]) // aperçu réutilisé
        explorer.reset()
        #expect(explorer.isHome && explorer.shelves.isEmpty)
    }
}

/// Échoue au premier appel, puis délègue au client démo.
actor FailOnce {
    let demo = DemoSpeakerClient(latency: .zero)
    var failed = false

    func load(_ location: RadioBrowseLocation, from: Int, count: Int) async throws -> RadioBrowsePage {
        if !failed {
            failed = true
            throw KEFError.offline
        }
        return try await demo.browseRadios(location, from: from, count: count)
    }
}
