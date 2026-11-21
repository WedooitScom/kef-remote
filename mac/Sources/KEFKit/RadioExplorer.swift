import Foundation
import Observation

/// Présentation d'une liste de l'explorateur (déduite du chemin parcouru).
public enum RadioExplorerStyle: Sendable, Equatable {
    /// Genres et sous-genres : tuiles colorées.
    case genres
    /// Régions, pays, villes : drapeaux.
    case countries
    /// Langues : pastille du code de langue.
    case languages
    /// Étagères (populaires, tendance…) et listes de stations.
    case stations

    /// Style d'un point d'entrée.
    public init(_ directory: RadioDirectory) {
        switch directory {
        case .genres: self = .genres
        case .countries: self = .countries
        case .languages: self = .languages
        default: self = .stations
        }
    }

    /// Style d'un raffinement (« affiner par pays » → liste de pays).
    public init(_ facet: RadioFacet) {
        switch facet {
        case .genre: self = .genres
        case .country: self = .countries
        case .language: self = .languages
        }
    }
}

/// État de chargement d'une page de l'explorateur.
public enum RadioExplorerLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Une liste de l'explorateur : chargement par pages de `pageSize` rows, raffinements mis
/// à part (puces au-dessus de la liste), filtrage local par nom sur ce qui est chargé.
@MainActor
@Observable
public final class RadioExplorerPage: Identifiable {
    public nonisolated let id = UUID()
    public let location: RadioBrowseLocation
    /// Libellé du fil d'Ariane (nom de la row ou du point d'entrée choisi).
    public let title: String
    /// Dossier dont une liste « Tout de: X » reprend toutes les stations (« Jazz ») : le fil
    /// d'Ariane dit « Toutes les stations », l'en-tête rappelle le dossier.
    public let scope: String?
    public let style: RadioExplorerStyle

    /// Dossiers et stations, dans l'ordre de l'enceinte (raffinements exclus).
    public private(set) var items: [RadioBrowseItem] = []
    /// Raffinements (« Par localité », « Par langue », « Genre »…).
    public private(set) var refinements: [RadioBrowseItem] = []
    /// Titre renvoyé par l'enceinte (« Région: Europe »), s'il est parlant.
    public private(set) var listTitle: String?
    public private(set) var totalCount: Int?
    public private(set) var state: RadioExplorerLoadState = .idle
    /// Erreur sur une page suivante (la liste déjà chargée reste affichée).
    public private(set) var loadMoreError: String?
    /// Filtre local (nom de station / de dossier) sur ce qui est déjà chargé.
    public var filterText = ""

    /// Chemin final (après redirection) : les pages suivantes partent de là.
    private var resolvedPath: String?
    private var nextOffset = 0
    private var exhausted = false
    @ObservationIgnored var loadTask: Task<Void, Never>?

    public init(location: RadioBrowseLocation, title: String, style: RadioExplorerStyle, scope: String? = nil) {
        self.location = location
        self.title = title
        self.style = style
        self.scope = scope
    }

    /// Titre d'en-tête de la liste : le dossier pour une liste « Tout de », sinon `title`.
    public var headerTitle: String { scope ?? title }

    public var isLoading: Bool { state == .loading }
    public var hasMore: Bool { !exhausted && state == .loaded }
    public var stations: [Station] { items.compactMap(\.station) }
    public var folders: [RadioBrowseItem] { items.filter(\.isFolder) }

    /// Dossiers puis stations correspondant au filtre local.
    public var filteredItems: [RadioBrowseItem] {
        let query = RadioCatalog.fold(filterText.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return items }
        return items.filter { RadioCatalog.fold($0.title).contains(query) }
    }

    /// Nombre de stations annoncé (total moins les raffinements), sinon chargé.
    public var announcedCount: Int? {
        guard let totalCount else { return nil }
        return max(0, totalCount - refinements.count)
    }

    /// Emplacement de la page suivante (`nil` si tout est chargé).
    var nextLocation: RadioBrowseLocation {
        resolvedPath.map(RadioBrowseLocation.path) ?? location
    }

    func begin() -> (location: RadioBrowseLocation, offset: Int)? {
        guard state != .loading, !exhausted else { return nil }
        let first = state != .loaded
        if first {
            items = []
            refinements = []
            nextOffset = 0
        }
        state = .loading
        loadMoreError = nil
        return (nextLocation, nextOffset)
    }

    func apply(_ page: RadioBrowsePage) {
        resolvedPath = page.path
        if listTitle == nil { listTitle = page.title }
        totalCount = page.totalCount ?? totalCount
        var seen = Set(items.map(\.id) + refinements.map(\.id))
        for item in page.items where seen.insert(item.id).inserted {
            if item.facet != nil { refinements.append(item) } else { items.append(item) }
        }
        nextOffset = page.nextOffset
        exhausted = !page.hasMore
        state = .loaded
    }

    func fail(_ message: String) {
        if items.isEmpty && refinements.isEmpty {
            state = .failed(message)
        } else {
            // Page suivante en échec : on garde la liste, on proposera de réessayer.
            state = .loaded
            loadMoreError = message
        }
    }

    /// Repart de zéro au prochain chargement (bouton « Réessayer » d'une liste vide).
    func resetForRetry() {
        guard case .failed = state else { return }
        state = .idle
        exhausted = false
    }
}

/// Explorateur de radios : pile de listes (fil d'Ariane), accueil = pile vide.
@MainActor
@Observable
public final class RadioExplorerModel {
    public typealias Loader = @Sendable (RadioBrowseLocation, Int, Int) async throws -> RadioBrowsePage

    public static let pageSize = 50
    /// Libellé d'une liste « Tout de » dans le fil d'Ariane.
    public static var allStationsTitle: String { localized("Toutes les stations") }

    public private(set) var stack: [RadioExplorerPage] = []
    /// Aperçus de l'accueil (étagères), réutilisés à l'ouverture de l'étagère.
    public private(set) var shelves: [RadioDirectory: RadioExplorerPage] = [:]

    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private var generation = 0

    public init(loader: @escaping Loader) {
        self.loader = loader
    }

    public var current: RadioExplorerPage? { stack.last }
    public var isHome: Bool { stack.isEmpty }

    // MARK: Navigation

    /// Ouvre un point d'entrée (Pays, Genres, Langues, étagères) au-dessus de l'accueil.
    @discardableResult
    public func open(_ directory: RadioDirectory) -> RadioExplorerPage {
        let page = shelves[directory] ?? RadioExplorerPage(location: .directory(directory), title: directory.title,
                                                           style: RadioExplorerStyle(directory))
        stack = [page]
        start(page)
        return page
    }

    /// Ouvre un dossier ou un raffinement de la liste courante ; `nil` pour une station
    /// (elle se joue, elle ne s'ouvre pas).
    @discardableResult
    public func open(_ item: RadioBrowseItem) -> RadioExplorerPage? {
        let style: RadioExplorerStyle
        switch item.kind {
        case .station:
            return nil
        case .refinement(let facet):
            style = RadioExplorerStyle(facet)
        case .folder:
            // Sous-genres d'un genre, pays d'une région… ; une liste « Tout de » est une liste de stations.
            style = item.isAllOf ? .stations : (current?.style ?? .stations)
        }
        var title = item.facet.map { facet in item.activeValue.map { facet.activeLabel($0) } ?? facet.label }
            ?? item.displayTitle
        // « Genres › Jazz › Jazz » : la liste « Tout de: Jazz » ouverte depuis « Jazz » se
        // nomme « Toutes les stations » dans le fil d'Ariane (le dossier reste en en-tête).
        var scope: String?
        if item.isAllOf {
            scope = item.displayTitle
            if let parent = current?.title, RadioCatalog.fold(parent) == RadioCatalog.fold(item.displayTitle) {
                title = Self.allStationsTitle
            }
        }
        let page = RadioExplorerPage(location: .path(item.path), title: title, style: style, scope: scope)
        stack.append(page)
        start(page)
        return page
    }

    public func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
    }

    /// Revient à la liste `page` du fil d'Ariane (`nil` = accueil).
    public func pop(to page: RadioExplorerPage?) {
        guard let page else { stack = []; return }
        guard let index = stack.firstIndex(where: { $0 === page }) else { return }
        stack.removeSubrange((index + 1)...)
    }

    public func popToRoot() { stack = [] }

    /// Oublie tout (changement d'enceinte) : accueil, aperçus à recharger.
    public func reset() {
        generation += 1
        for page in stack { page.loadTask?.cancel() }
        for page in shelves.values { page.loadTask?.cancel() }
        stack = []
        shelves = [:]
    }

    // MARK: Chargement

    /// Précharge les aperçus d'étagères de l'accueil (une seule fois ; ceux en échec sont retentés).
    public func loadShelves(_ directories: [RadioDirectory] = [.popular, .trending]) {
        for directory in directories {
            if let existing = shelves[directory] {
                if case .failed = existing.state { retry(existing) }
                continue
            }
            let page = RadioExplorerPage(location: .directory(directory), title: directory.title, style: .stations)
            shelves[directory] = page
            start(page)
        }
    }

    /// Page suivante (défilement en bas de liste).
    public func loadMore(_ page: RadioExplorerPage) {
        guard page.hasMore else { return }
        start(page)
    }

    /// Réessayer après une erreur (première page ou page suivante).
    public func retry(_ page: RadioExplorerPage) {
        page.resetForRetry()
        start(page)
    }

    /// Attend la fin du chargement en cours d'une page (tests, captures).
    public func waitUntilLoaded(_ page: RadioExplorerPage) async {
        await page.loadTask?.value
    }

    private func start(_ page: RadioExplorerPage) {
        guard let request = page.begin() else { return }
        let loader = loader
        let gen = generation
        page.loadTask = Task { [weak self, weak page] in
            do {
                let result = try await loader(request.location, request.offset, Self.pageSize)
                guard let self, gen == self.generation, let page else { return }
                page.apply(result)
            } catch {
                guard let self, gen == self.generation, let page, !Task.isCancelled else { return }
                page.fail(describe(error))
            }
        }
    }
}
