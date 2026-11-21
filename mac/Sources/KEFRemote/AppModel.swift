import AppKit
import KEFKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Modèle racine de l'application : configuration, enceinte, favoris, recherche, découverte.
@MainActor
@Observable
final class AppModel {
    let store = SpeakerStore()
    let favorites: FavoritesStore
    let discovery = SpeakerDiscovery()
    let isDemo: Bool
    private(set) var host: String?

    // Historique radio de l'enceinte (suggestions quand il n'y a aucun favori).
    private(set) var history: [Station] = []
    private(set) var historyLoaded = false

    // Recherche de stations (avec anti-rebond).
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    private(set) var searchResults: [Station] = []
    private(set) var isSearching = false
    private(set) var searchError: String?
    private var searchTask: Task<Void, Never>?

    /// Explorateur de radios (pays, genres, langues, étagères), lecture seule côté enceinte.
    let explorer: RadioExplorerModel
    /// Panneau de l'explorateur ouvert (designs fenêtrés ; le Baladeur a son propre menu).
    var showsExplorer = false

    /// Design imposé pour la session (`--design <nom>`, captures `--snapshot`), prioritaire
    /// sur la préférence enregistrée et jamais mémorisé.
    var designOverride: AppDesign?

    /// Design affiché (override de session, sinon préférence enregistrée).
    var currentDesign: AppDesign {
        designOverride ?? AppDesign.stored(UserDefaults.standard.string(forKey: AppDesign.storageKey))
    }

    /// Message éphémère (import, erreurs…).
    var toast: String?
    private var toastTask: Task<Void, Never>?

    @ObservationIgnored private var nowPlaying: NowPlayingBridge?
    @ObservationIgnored private var keyMonitor: Any?

    static let hostKey = "speakerHost"

    init() {
        let env = ProcessInfo.processInfo.environment
        let args = CommandLine.arguments
        isDemo = args.contains("--demo") || ["1", "true", "yes", "oui"].contains((env["KEF_DEMO"] ?? "").lowercased())

        // Priorité : --host <ip> (non mémorisé), puis UserDefaults, puis KEF_HOST.
        var initialHost: String?
        if let i = args.firstIndex(of: "--host"), args.indices.contains(i + 1) {
            initialHost = try? HostValidator.normalize(args[i + 1])
        }
        initialHost = initialHost ?? UserDefaults.standard.string(forKey: Self.hostKey)
            ?? env["KEF_HOST"].flatMap { try? HostValidator.normalize($0) }
        host = initialHost

        if let i = args.firstIndex(of: "--design"), args.indices.contains(i + 1) {
            designOverride = AppDesign.parse(args[i + 1])
        }

        if Snapshotter.isRequested {
            // Captures : favoris temporaires (jamais ceux de l'utilisateur), garnis en démo.
            favorites = Snapshotter.makeTemporaryFavorites(seedDemo: isDemo)
        } else {
            // En démo, fichier séparé pour ne pas mélanger des stations fictives aux vrais favoris.
            favorites = FavoritesStore(fileURL: FavoritesStore.defaultURL(fileName: isDemo ? "favorites-demo.json" : "favorites.json"))
        }

        let store = store
        explorer = RadioExplorerModel { location, from, count in
            try await store.browseRadios(location, from: from, count: count)
        }

        connect()
        nowPlaying = NowPlayingBridge(model: self)
        installKeyMonitor()
        if !isDemo && host == nil { discovery.start() }
        Snapshotter.scheduleIfRequested(model: self)
    }

    // MARK: - Connexion

    func connect() {
        history = []
        historyLoaded = false
        searchResults = []
        explorer.reset()
        if isDemo {
            store.connect(DemoSpeakerClient())
        } else if let host {
            store.connect(KEFHTTPClient(host: host))
        } else {
            store.connect(nil)
        }
        Task { await loadHistory() }
    }

    /// Enregistre une nouvelle adresse (UserDefaults) et se reconnecte.
    func setHost(_ raw: String) throws {
        let normalized = try HostValidator.normalize(raw)
        UserDefaults.standard.set(normalized, forKey: Self.hostKey)
        host = normalized
        connect()
    }

    var speakerTitle: String {
        store.snapshot.name ?? (isDemo ? String(localized: "Démo") : host ?? "KEF Remote")
    }

    // MARK: - Radios

    func loadHistory() async {
        guard store.hasClient else { return }
        // Laisse le temps à la connexion de s'établir.
        for _ in 0..<50 where !store.status.isOnline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        do {
            history = try await store.radioHistory()
        } catch {
            history = []
        }
        historyLoaded = true
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            searchError = nil
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450)) // anti-rebond
            guard !Task.isCancelled else { return }
            do {
                let results = try await store.searchStations(query)
                guard !Task.isCancelled else { return }
                searchResults = results
                searchError = results.isEmpty ? String(localized: "Aucune station trouvée") : nil
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                searchError = describe(error)
            }
            isSearching = false
        }
    }

    func play(_ station: Station) {
        Task { await store.playStation(station) }
    }

    // MARK: - Explorateur

    /// Ouvre (ou ferme) l'explorateur ; précharge les aperçus de l'accueil.
    func toggleExplorer() {
        withAnimation(.spring(duration: 0.35)) { showsExplorer.toggle() }
        if showsExplorer { explorer.loadShelves() }
    }

    /// Ajoute / retire une station des favoris, avec un bref message.
    func toggleFavorite(_ station: Station) {
        withAnimation { favorites.toggle(station) }
        showFavoriteToast(station)
    }

    // MARK: - Précédent / suivant

    /// Plan des boutons précédent / suivant : sur une radio airable, zapping dans l'ordre
    /// des favoris (sinon des radios récentes) ; ailleurs, piste précédente / suivante si
    /// l'enceinte l'annonce dans `controls`.
    func skipPlan(_ direction: SkipDirection) -> SkipPlan {
        TransportLogic.skipPlan(direction, snapshot: store.snapshot, isOnline: store.status.isOnline,
                                station: store.activeStation, favorites: favorites.items, fallback: history)
    }

    /// Exécute précédent / suivant (boutons, raccourcis, molette, touches média).
    func skip(_ direction: SkipDirection) {
        let plan = skipPlan(direction)
        switch plan.action {
        case .station(let station):
            play(station)
        case .track:
            Task { direction == .next ? await store.nextTrack() : await store.previousTrack() }
        case .none:
            NSSound.beep()
        }
    }

    func playFavorite(at index: Int) {
        guard favorites.items.indices.contains(index) else { return }
        play(favorites.items[index])
    }

    func isCurrent(_ station: Station) -> Bool {
        station.isSameStation(as: store.snapshot.currentStation)
    }

    /// Ajoute (ou retire) la station en cours des favoris.
    func toggleCurrentFavorite() {
        guard let station = store.snapshot.currentStation else { return }
        favorites.toggle(station)
        showFavoriteToast(station)
    }

    func importFavorites() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Importer des radios favorites")
        panel.message = String(localized: "Choisissez un fichier favorites.json (par exemple celui du client web KEF Remote).")
        panel.prompt = String(localized: "Importer")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = try favorites.importFile(at: url)
            showToast(added == 0 ? String(localized: "Aucune nouvelle station à importer")
                                  : String(localized: "\(added) stations importées"))
        } catch {
            showToast(String(localized: "Import impossible : fichier illisible"))
        }
    }

    func revealFavoritesFile() {
        let url = favorites.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func showFavoriteToast(_ station: Station) {
        showToast(favorites.contains(station) ? String(localized: "« \(station.title) » ajoutée aux favoris")
                                              : String(localized: "« \(station.title) » retirée des favoris"))
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }

    // MARK: - Clavier

    /// Espace = lecture/pause, sauf pendant une saisie de texte.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard event.keyCode == 49, mods.isEmpty else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                // Pas pendant une saisie (recherche, adresse IP…).
                guard let self, !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
                Task { await self.store.playPause() }
                return true
            }
            return handled ? nil : event
        }
    }
}
