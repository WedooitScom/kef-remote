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
///   pour le Baladeur, écrans de menu (`main-baladeur-menu`, `-favorites`, `-options`, `-sources`).
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

    private static func show(_ design: AppDesign?, model: AppModel) async {
        guard let design else { return }
        model.designOverride = design
        // Transition, chargement des images et couleur de pochette.
        try? await Task.sleep(for: .seconds(1.6))
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && ($0.contentView?.bounds.width ?? 0) > 200 }
    }

    private static func captureMainWindow(to dir: URL, name: String?) {
        for window in NSApp.windows where window.isVisible {
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
