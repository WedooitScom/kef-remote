import AppKit
import KEFKit
import SwiftUI

/// Option de développement : `--snapshot <dossier>` rend les fenêtres de l'app en PNG
/// (sans autorisation « Enregistrement de l'écran », l'app dessine ses propres vues),
/// puis quitte si `--quit-after-snapshot` est aussi passé.
///
/// - `--design <nom>` : capture ce design (`main-<nom>.png`, `menubar-<nom>.png`) ;
///   `--design all` : tous les designs d'un coup. Sans `--design`, le design enregistré
///   (`KEF Remote.png`, `menubar.png`).
/// - `--appearance dark|light` : impose l'apparence de l'app (vérifier le mode sombre).
/// - `--snapshot-size 900x560[,700x900…]` : en plus, capture chaque design à ces tailles de
///   fenêtre (`main-<nom>-900x560.png`) ; `min` = taille minimale du design (`-min`).
/// - `--snapshot-extras` (démo) : en plus, fenêtre à la taille minimale (`-min`), état
///   veille (`-veille`), structure des menus (`menus.txt`) et Réglages (`reglages.png`) ;
///   planche des pochettes de repli de chaque style (`artwork.png`) ;
///   pour le Baladeur, écrans de menu (`main-baladeur-menu`, `-favorites`, `-options`, `-sources`) ;
///   explorateur de radios (`main-<nom>-explorer`, `-explorer-genres`, `-explorer-stations`,
///   `-explorer-stations-min`, `-explorer-pays` ; Baladeur : `main-baladeur-explore`, `-explore-genres`, `-explore-stations`).
///
/// Les favoris viennent d'un fichier temporaire (garni des stations fictives en démo),
/// jamais de celui de l'utilisateur ; en démo, une radio est mise en lecture.
///
/// NB : le flou « derrière la fenêtre » (vibrancy) n'apparaît pas dans ces rendus.
@MainActor
enum Snapshotter {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static var isRequested: Bool { directory != nil }

    private static var temporaryFavoritesDirectory: URL?

    /// Favoris jetables pour les captures (supprimés à la fin).
    static func makeTemporaryFavorites(seedDemo: Bool) -> FavoritesStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kef-snapshot-\(UUID().uuidString)", isDirectory: true)
        temporaryFavoritesDirectory = dir
        let store = FavoritesStore(fileURL: dir.appendingPathComponent("favorites.json"))
        if seedDemo {
            for station in DemoSpeakerClient.demoStations.prefix(8) { store.add(station) }
        }
        return store
    }

    /// Designs demandés : `nil` = design courant (noms de fichiers historiques).
    private static func requestedDesigns() -> [AppDesign?] {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--design"), args.indices.contains(i + 1) else { return [nil] }
        if args[i + 1].lowercased() == "all" { return AppDesign.allCases }
        return [AppDesign.parse(args[i + 1])]
    }

    /// Tailles demandées par `--snapshot-size` (`nil` = taille minimale du design).
    static func requestedSizes() -> [NSSize?] {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot-size"), args.indices.contains(i + 1) else { return [] }
        return args[i + 1].split(separator: ",").compactMap { token -> NSSize?? in
            let t = token.trimmingCharacters(in: .whitespaces).lowercased()
            if t == "min" { return .some(nil) }
            let parts = t.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2, parts[0] >= 200, parts[1] >= 200 else { return nil }
            return .some(NSSize(width: parts[0], height: parts[1]))
        }
    }

    static func scheduleIfRequested(model: AppModel) {
        guard let dir = directory else { return }
        let args = CommandLine.arguments
        let quit = args.contains("--quit-after-snapshot")
        let extras = args.contains("--snapshot-extras") && model.isDemo
        let designs = requestedDesigns()
        if let i = args.firstIndex(of: "--appearance"), args.indices.contains(i + 1) {
            NSApp.appearance = NSAppearance(named: args[i + 1].lowercased() == "dark" ? .darkAqua : .aqua)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Démo uniquement : une radio en lecture (aucune commande vers une vraie enceinte).
            if model.isDemo, let station = model.favorites.items.dropFirst().first {
                model.play(station)
                try? await Task.sleep(for: .seconds(1.5))
            }

            for design in designs {
                await show(design, model: model)
                let suffix = design.map { "-\($0.rawValue)" } ?? ""
                captureMainWindow(to: dir, name: design == nil ? nil : "main\(suffix)")
                await captureMiniPlayer(model: model, to: dir.appendingPathComponent("menubar\(suffix).png"))
            }

            // Tailles imposées (`--snapshot-size`).
            let sizes = requestedSizes()
            if !sizes.isEmpty, let window = mainWindow() {
                let frame = window.frame
                for size in sizes {
                    for design in designs {
                        await show(design, model: model)
                        let target = size ?? DesignLayout.minimumSize(design ?? model.currentDesign)
                        window.setContentSize(target)
                        try? await Task.sleep(for: .seconds(0.8))
                        let label = size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "min"
                        captureMainWindow(to: dir, name: "main\(design.map { "-\($0.rawValue)" } ?? "")-\(label)")
                    }
                }
                window.setFrame(frame, display: true)
                try? await Task.sleep(for: .seconds(0.5))
            }

            if extras && designs.contains(.baladeur) {
                // Baladeur : écrans de menu (`main-baladeur-<écran>`).
                await show(.baladeur, model: model)
                for screen in ["menu", "favorites", "options", "sources"] {
                    NotificationCenter.default.post(name: BaladeurScreen.showNotification, object: screen)
                    try? await Task.sleep(for: .seconds(0.8))
                    captureMainWindow(to: dir, name: "main-baladeur-\(screen)")
                }
                NotificationCenter.default.post(name: BaladeurScreen.showNotification, object: "nowPlaying")
            }

            if extras {
                // Explorateur (avant les Réglages : une seule fenêtre visible).
                await captureExplorer(model: model, designs: designs, to: dir)
            }

            if extras {
                // Taille minimale de la fenêtre.
                if let window = mainWindow() {
                    let frame = window.frame
                    for design in designs {
                        await show(design, model: model)
                        window.setContentSize(DesignLayout.minimumSize(design ?? model.currentDesign))
                        try? await Task.sleep(for: .seconds(0.6))
                        captureMainWindow(to: dir, name: "main\(design.map { "-\($0.rawValue)" } ?? "")-min")
                    }
                    window.setFrame(frame, display: true)
                }
                // Veille.
                await model.store.setPower(on: false)
                try? await Task.sleep(for: .seconds(1))
                for design in designs {
                    await show(design, model: model)
                    let suffix = design.map { "-\($0.rawValue)" } ?? ""
                    captureMainWindow(to: dir, name: "main\(suffix)-veille")
                    await captureMiniPlayer(model: model, to: dir.appendingPathComponent("menubar\(suffix)-veille.png"))
                }
                await model.store.setPower(on: true)
                writeMenus(to: dir.appendingPathComponent("menus.txt"))
                writeArtworkSheet(to: dir.appendingPathComponent("artwork.png"))
                // Réglages (choix du design par vignettes).
                let main = mainWindow()
                if let appMenu = NSApp.mainMenu?.items.first?.submenu,
                   let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
                    appMenu.performActionForItem(at: index)
                }
                try? await Task.sleep(for: .seconds(2))
                for window in NSApp.windows where window.isVisible && window !== main {
                    if let view = window.contentView, view.bounds.width > 200 {
                        write(view: view, to: dir.appendingPathComponent("reglages.png"))
                    }
                }
            }

            if let tmp = temporaryFavoritesDirectory {
                try? FileManager.default.removeItem(at: tmp)
            }
            if quit { NSApp.terminate(nil) }
        }
    }

    /// Explorateur (démo) : accueil, genres, liste de stations (avec une station déjà en
    /// favori et une ajoutée à l'instant, pour l'étoile et le message), pays d'Europe.
    private static func captureExplorer(model: AppModel, designs: [AppDesign?], to dir: URL) async {
        let explorer = model.explorer
        func open(_ title: String, in page: RadioExplorerPage?) async -> RadioExplorerPage? {
            guard let item = page?.items.first(where: { $0.title == title || $0.displayTitle == title && $0.isAllOf }),
                  let next = explorer.open(item) else { return nil }
            await explorer.waitUntilLoaded(next)
            return next
        }
        /// Genres › Jazz › Tout Jazz ; deux stations en favori (dont une ajoutée avec message).
        func openJazzStations() async {
            explorer.popToRoot()
            let genres = explorer.open(.genres)
            await explorer.waitUntilLoaded(genres)
            let jazz = await open("Jazz", in: genres)
            if let all = jazz?.items.first(where: \.isAllOf), let leaf = explorer.open(all) {
                await explorer.waitUntilLoaded(leaf)
                let stations = leaf.stations
                if stations.count > 2, !model.favorites.contains(stations[2]) { model.favorites.add(stations[2]) }
                if stations.count > 1 {
                    if model.favorites.contains(stations[1]) { model.favorites.remove(stations[1]) }
                    model.toggleFavorite(stations[1])
                }
            }
        }

        for design in designs {
            guard (design ?? model.currentDesign) != .baladeur else { continue }
            await show(design, model: model)
            let name = "main\(design.map { "-\($0.rawValue)" } ?? "")-explorer"
            explorer.popToRoot()
            if !model.showsExplorer { model.toggleExplorer() }
            for page in explorer.shelves.values { await explorer.waitUntilLoaded(page) }
            try? await Task.sleep(for: .seconds(1.2))
            captureMainWindow(to: dir, name: name)

            let genres = explorer.open(.genres)
            await explorer.waitUntilLoaded(genres)
            try? await Task.sleep(for: .seconds(0.8))
            captureMainWindow(to: dir, name: "\(name)-genres")

            await openJazzStations()
            try? await Task.sleep(for: .seconds(1))
            captureMainWindow(to: dir, name: "\(name)-stations")
            // Même liste à la taille minimale de la fenêtre (mise en page adaptative).
            if let window = mainWindow() {
                let frame = window.frame
                window.setContentSize(DesignLayout.minimumSize(design ?? model.currentDesign))
                try? await Task.sleep(for: .seconds(0.8))
                captureMainWindow(to: dir, name: "\(name)-stations-min")
                window.setFrame(frame, display: true)
                try? await Task.sleep(for: .seconds(0.4))
            }

            explorer.popToRoot()
            let countries = explorer.open(.countries)
            await explorer.waitUntilLoaded(countries)
            _ = await open("Europe", in: countries)
            try? await Task.sleep(for: .seconds(0.8))
            captureMainWindow(to: dir, name: "\(name)-pays")
            model.showsExplorer = false
        }

        if designs.contains(.baladeur) {
            await show(.baladeur, model: model)
            explorer.popToRoot()
            explorer.loadShelves()
            NotificationCenter.default.post(name: BaladeurScreen.showNotification, object: "explore")
            try? await Task.sleep(for: .seconds(0.8))
            captureMainWindow(to: dir, name: "main-baladeur-explore")
            let genres = explorer.open(.genres)
            await explorer.waitUntilLoaded(genres)
            try? await Task.sleep(for: .seconds(0.8))
            captureMainWindow(to: dir, name: "main-baladeur-explore-genres")
            await openJazzStations()
            try? await Task.sleep(for: .seconds(0.8))
            captureMainWindow(to: dir, name: "main-baladeur-explore-stations")
            explorer.popToRoot()
            NotificationCenter.default.post(name: BaladeurScreen.showNotification, object: "nowPlaying")
        }
    }

    private static func show(_ design: AppDesign?, model: AppModel) async {
        guard let design else { return }
        model.designOverride = design
        // Transition, chargement des images et couleur de pochette.
        try? await Task.sleep(for: .seconds(1.6))
    }

    private static func mainWindow() -> NSWindow? {
        mainWindows().first
    }

    /// Fenêtre principale (identifiant SwiftUI « main ») ; à défaut, toute fenêtre visible
    /// assez grande. Écarte une fenêtre Réglages restaurée d'un lancement précédent.
    private static func mainWindows() -> [NSWindow] {
        let visible = NSApp.windows.filter { $0.isVisible && ($0.contentView?.bounds.width ?? 0) > 200 }
        let main = visible.filter { $0.identifier?.rawValue.hasPrefix("main") == true }
        return main.isEmpty ? visible : main
    }

    private static func captureMainWindow(to dir: URL, name: String?) {
        for window in mainWindows() {
            guard let view = window.contentView, view.bounds.width > 200 else { continue }
            let title = name ?? (window.title.isEmpty ? "window-\(window.windowNumber)" : window.title)
            write(view: view, to: dir.appendingPathComponent("\(title).png"))
        }
    }

    /// Mini-lecteur de la barre des menus, rendu hors écran.
    private static func captureMiniPlayer(model: AppModel, to url: URL) async {
        let host = NSHostingView(rootView: MiniPlayerRoot().environment(model)
            .background(Color(nsColor: .windowBackgroundColor)))
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                            backing: .buffered, defer: false)
        panel.contentView = host
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(1.5))
        write(view: host, to: url)
        panel.orderOut(nil)
    }

    /// Planche des pochettes de repli : une ligne par style, en grand (96 pt) et en petit (24 pt).
    private static func writeArtworkSheet(to url: URL) {
        let titles = ["Radio Cuivre", "Onde Coaxiale FM", "Basse Fréquence", "Kent Info", "Zénith 80"]
        let sheet = VStack(alignment: .leading, spacing: 14) {
            ForEach(ArtworkStyle.allCases, id: \.self) { style in
                HStack(spacing: 12) {
                    Text(style.rawValue).font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 90, alignment: .leading)
                    ForEach(titles, id: \.self) { title in
                        FallbackArtworkView(key: title, title: title, style: style)
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(titles, id: \.self) { title in
                                FallbackArtworkView(key: title, title: title, style: style)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        }
                        HStack(spacing: 6) {
                            ForEach([24, 200, 280, 340, 150], id: \.self) { hue in
                                DemoArtworkView(hue: hue, style: style)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.93))
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let image = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    /// Structure de la barre des menus (vérification des menus ajoutés).
    private static func writeMenus(to url: URL) {
        var lines: [String] = []
        func walk(_ menu: NSMenu, depth: Int) {
            for item in menu.items where !item.isSeparatorItem {
                var line = String(repeating: "  ", count: depth) + item.title
                if !item.keyEquivalent.isEmpty {
                    let mods = item.keyEquivalentModifierMask
                    line += "  [" + (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "")
                        + (mods.contains(.shift) ? "⇧" : "") + (mods.contains(.command) ? "⌘" : "") + item.keyEquivalent + "]"
                }
                if item.state == .on { line += "  ✓" }
                lines.append(line)
                if let sub = item.submenu, depth < 2 { walk(sub, depth: depth + 1) }
            }
        }
        if let main = NSApp.mainMenu { walk(main, depth: 0) }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func write(view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
