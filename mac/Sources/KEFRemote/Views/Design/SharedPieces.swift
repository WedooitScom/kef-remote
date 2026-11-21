import AppKit
import CoreImage
import ImageIO
import KEFKit
import SwiftUI

// Briques communes aux designs : textes de lecture, interactions des favoris, contenu
// « radios » (recherche / suggestions / favoris), actions du mini-lecteur, molette de la
// souris, couleur de pochette. Chaque design ne fait que la mise en page.

// MARK: - Textes de lecture

@MainActor
enum NowPlayingText {
    /// Titre principal (fenêtre).
    static func title(_ model: AppModel) -> String {
        let store = model.store, s = store.snapshot
        guard store.status.isOnline else { return store.status == .notConfigured ? "Bienvenue" : "Enceinte indisponible" }
        if !s.isOn { return "En veille" }
        if let source = s.source, source != .wifi { return source.label }
        return s.player.title ?? s.player.station?.title ?? "Rien en lecture"
    }

    /// Sous-titre (fenêtre).
    static func subtitle(_ model: AppModel) -> String {
        let store = model.store, s = store.snapshot
        guard store.status.isOnline else { return store.status.label }
        if !s.isOn { return "Touchez ⏻ ou une radio pour allumer" }
        if let source = s.source, source != .wifi { return "Entrée \(source.label.lowercased())" }
        if let station = s.player.station, s.player.title != station.title { return station.title }
        return s.player.artist ?? (s.player.state == .stopped ? "Choisissez une radio" : " ")
    }

    /// Titre court (mini-lecteur).
    static func compactTitle(_ model: AppModel) -> String {
        let store = model.store, s = store.snapshot
        guard store.status.isOnline else { return "Hors ligne" }
        if !s.isOn { return "En veille" }
        if let source = s.source, source != .wifi { return source.label }
        return s.player.title ?? s.player.station?.title ?? "Rien en lecture"
    }

    /// Sous-titre court (mini-lecteur).
    static func compactSubtitle(_ model: AppModel) -> String {
        let store = model.store, s = store.snapshot
        guard store.status.isOnline else { return store.status.label }
        if !s.isOn { return s.modelLabel ?? "KEF" }
        if let station = s.player.station, s.player.title != station.title { return station.title }
        return s.player.artist ?? " "
    }

    /// Bandeau d'état en capitales : « EN DIRECT · WIFI », « VEILLE », « HORS LIGNE »…
    static func kicker(_ model: AppModel) -> String {
        let store = model.store, s = store.snapshot
        switch store.status {
        case .notConfigured: return "AUCUNE ENCEINTE"
        case .connecting: return "CONNEXION…"
        case .offline: return "HORS LIGNE"
        case .online: break
        }
        if !s.isOn { return "VEILLE" }
        let source = (s.source ?? .wifi).panelLabel
        if let src = s.source, src != .wifi { return "ENTRÉE · \(source)" }
        switch s.player.state {
        case .playing: return (s.player.isLive ? "EN DIRECT" : "EN LECTURE") + " · \(source)"
        case .paused: return "EN PAUSE · \(source)"
        case .stopped: return "ARRÊT · \(source)"
        }
    }

    /// Pochette (ou logo de station) à afficher, si l'enceinte est allumée en Wi‑Fi.
    static func cover(_ model: AppModel) -> String? {
        let s = model.store.snapshot
        guard model.store.status.isOnline, s.isOn, s.source == .wifi || s.source == nil else { return nil }
        return s.player.coverURL ?? s.player.station?.icon
    }
}

// MARK: - Favoris : comportement commun

/// Tap = lecture, glisser-déposer pour réordonner, menu contextuel. Identique dans tous
/// les designs ; seul l'aspect de la cible de dépôt (`dropTarget`) est laissé au design.
struct FavoriteInteractions: ViewModifier {
    @Environment(AppModel.self) private var model
    let station: Station
    let index: Int
    @Binding var dropTarget: String?

    func body(content: Content) -> some View {
        content
            .onTapGesture { model.play(station) }
            .draggable(station.id) {
                StationLogo(station: station).frame(width: 64, height: 64)
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first else { return false }
                withAnimation(.spring(duration: 0.3)) { model.favorites.move(id: id, before: station.id) }
                return true
            } isTargeted: { targeted in
                dropTarget = targeted ? station.id : (dropTarget == station.id ? nil : dropTarget)
            }
            .contextMenu {
                Button("Lire") { model.play(station) }
                Divider()
                if index > 0 {
                    Button("Déplacer en premier") {
                        withAnimation { model.favorites.move(id: station.id, before: model.favorites.items[0].id) }
                    }
                }
                Button("Retirer des favoris", role: .destructive) {
                    withAnimation { _ = model.favorites.remove(station) }
                }
            }
    }
}

extension View {
    func favoriteInteractions(station: Station, index: Int, dropTarget: Binding<String?>) -> some View {
        modifier(FavoriteInteractions(station: station, index: index, dropTarget: dropTarget))
    }
}

/// Contenu de la zone radios : résultats de recherche, suggestions (aucun favori) ou
/// favoris présentés par le design.
struct RadioContent<Favorites: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var favorites: () -> Favorites

    var body: some View {
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResults()
        } else if model.favorites.items.isEmpty {
            Suggestions()
        } else {
            favorites()
        }
    }
}

/// Étoile : ajouter / retirer la radio en cours des favoris.
struct CurrentFavoriteButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.designTheme) private var theme
    var size: CGFloat = 15

    var body: some View {
        let current = model.store.snapshot.currentStation
        let isFavorite = model.favorites.contains(current)
        Button { model.toggleCurrentFavorite() } label: {
            Label(isFavorite ? "Retirer la radio en cours" : "Ajouter la radio en cours",
                  systemImage: isFavorite ? "star.fill" : "star")
                .labelStyle(.iconOnly)
                .foregroundStyle(isFavorite ? theme.favorite : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .font(.system(size: size))
        .disabled(current == nil)
        .help(current.map { isFavorite ? "Retirer « \($0.title) » des favoris" : "Ajouter « \($0.title) » aux favoris" }
              ?? "Aucune radio airable en cours")
    }
}

/// Menu ⋯ des favoris (import, fichier, suggestions).
struct FavoritesMenu: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 15

    var body: some View {
        Menu {
            Button("Importer…") { model.importFavorites() }
            Button("Afficher le fichier dans le Finder") { model.revealFavoritesFile() }
            if model.favorites.items.isEmpty && model.favorites.suggestHistory {
                Divider()
                Button("Masquer les suggestions") { model.favorites.dismissSuggestions() }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: size))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .accessibilityLabel("Options des favoris")
    }
}

// MARK: - Mini-lecteur : actions communes

/// Ouvrir la fenêtre principale.
struct OpenMainWindowButton<Label: View>: View {
    @Environment(\.openWindow) private var openWindow
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        } label: { label() }
        .help("Ouvrir KEF Remote")
        .accessibilityLabel("Ouvrir KEF Remote")
    }
}

/// « Réglages… » / vignettes des designs / « Quitter » en bas du mini-lecteur.
struct MiniPlayerFooter: View {
    @Environment(\.openSettings) private var openSettings
    var uppercase = false
    /// Rangée de designs (choix rapide du style).
    var showsDesigns = true

    var body: some View {
        VStack(spacing: 8) {
            if showsDesigns {
                DesignSwatches()
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Button(uppercase ? "RÉGLAGES…" : "Réglages…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button(uppercase ? "QUITTER" : "Quitter") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Molette de la souris / trackpad

/// Reçoit les événements de défilement au-dessus de la vue sans intercepter les clics
/// (moniteur local + test de position). `delta` > 0 = vers le haut (doigts ou molette),
/// quel que soit le réglage « défilement naturel ».
struct ScrollWheelReader: NSViewRepresentable {
    var onScroll: (_ delta: CGFloat, _ precise: Bool) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ScrollWheelView, context: Context) {
        view.onScroll = onScroll
    }

    final class ScrollWheelView: NSView {
        var onScroll: ((CGFloat, Bool) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, event.window === window, !self.isHiddenOrHasHiddenAncestor else { return false }
                    let p = self.convert(event.locationInWindow, from: nil)
                    guard self.bounds.contains(p) else { return false }
                    let raw = event.scrollingDeltaY
                    guard raw != 0 else { return false }
                    let delta = event.isDirectionInvertedFromDevice ? -raw : raw
                    self.onScroll?(delta, event.hasPreciseScrollingDeltas)
                    return true
                }
                return handled ? nil : event
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}

/// Convertit le défilement en pas de volume (accumulation pour le trackpad).
@MainActor
final class ScrollAccumulator {
    private var pending: CGFloat = 0

    /// Renvoie le nombre de pas entiers à appliquer.
    func steps(for delta: CGFloat, precise: Bool) -> Int {
        if !precise { return delta > 0 ? 1 : -1 }
        pending += delta / 6
        let whole = pending.rounded(.towardZero)
        pending -= whole
        return Int(whole)
    }
}

// MARK: - Couleur de la pochette (designs immersif et pixel)

/// Couleur de fond tirée de la pochette, version floutée pour le fond plein cadre et
/// version pixelisée (design « Rétro pixel »),
/// mises en cache par URL (vignettes de 64 px : le flou est calculé une fois, sur le
/// processeur, au lieu d'un flou temps réel sur toute la fenêtre).
@MainActor
final class CoverColors {
    static let shared = CoverColors()
    private var cache: [String: SRGBColor] = [:]
    private var thumbnails: [String: CGImage] = [:]
    private var blurred: [String: CGImage] = [:]
    private var pixelated: [String: [SRGBColor]] = [:]
    private let context = CIContext(options: [.cacheIntermediates: false])

    func color(for source: String?) async -> SRGBColor {
        guard let source else { return DominantColor.fallback }
        if let cached = cache[source] { return cached }
        guard let image = await thumbnail(for: source, style: .immersif) else { return DominantColor.fallback } // échec réseau : pas de mise en cache
        let color = DominantColor.backgroundColor(for: image)
        cache[source] = color
        return color
    }

    /// Pochette très floutée (petite image, à agrandir en `scaledToFill`).
    func blurredImage(for source: String?) async -> CGImage? {
        guard let source else { return nil }
        if let cached = blurred[source] { return cached }
        guard let image = await thumbnail(for: source, style: .immersif) else { return nil }
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(image.width, image.height)) * 0.07)
            .cropped(to: input.extent)
        guard let result = context.createCGImage(output, from: input.extent) else { return nil }
        if blurred.count > 40 { blurred.removeAll() }
        blurred[source] = result
        return result
    }

    /// Pochette ou logo réduit à `side × side` couleurs (design « Rétro pixel »).
    func pixelArt(for source: String?, side: Int) async -> [SRGBColor]? {
        guard let source else { return nil }
        let key = "\(side)|\(source)"
        if let cached = pixelated[key] { return cached }
        let image: CGImage?
        if let hue = DemoArt.hue(from: source) {
            // Visuel de démo : la pochette pixel (grille de 12) rendue au pixel près.
            let renderer = ImageRenderer(content: DemoArtworkView(hue: hue, style: .pixel).frame(width: 12, height: 12))
            renderer.scale = 1
            image = renderer.cgImage
        } else {
            image = await thumbnail(for: source, style: .pixel)
        }
        guard let image, let colors = PixelArt.downsample(image, side: side, levels: DemoArt.hue(from: source) == nil ? 6 : 256)
        else { return nil }
        if pixelated.count > 160 { pixelated.removeAll() }
        pixelated[key] = colors
        return colors
    }

    /// Vignette de 64 px ; les visuels de démo sont dessinés dans le style demandé.
    private func thumbnail(for source: String, style: ArtworkStyle) async -> CGImage? {
        let demoHue = DemoArt.hue(from: source)
        let cacheKey = demoHue == nil ? source : "\(style.rawValue)|\(source)"
        if let cached = thumbnails[cacheKey] { return cached }
        var image: CGImage?
        if let hue = demoHue {
            let renderer = ImageRenderer(content: DemoArtworkView(hue: hue, style: style).frame(width: 64, height: 64))
            image = renderer.cgImage
        } else if let url = ImageURL.resolve(source),
                  let (data, _) = try? await URLSession.shared.data(from: url) {
            image = Self.thumbnail(data)
        }
        if let image {
            if thumbnails.count > 40 { thumbnails.removeAll() }
            thumbnails[cacheKey] = image
        }
        return image
    }

    private static func thumbnail(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}

// MARK: - Curseur de volume fin (immersif, éditorial)

/// Volume en filet : piste fine, glisser / cliquer, molette, flèches, VoiceOver.
struct ThinVolumeSlider: View {
    let store: SpeakerStore
    var track: Color
    var fill: Color
    var thickness: CGFloat = 2
    var knob: CGFloat = 10
    @State private var scroll = ScrollAccumulator()
    @FocusState private var focused: Bool

    var body: some View {
        let snap = store.snapshot
        let enabled = store.status.isOnline && snap.isOn
        let fraction = Double(snap.volume) / 100
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(track).frame(height: thickness)
                Rectangle().fill(fill).frame(width: max(0, w * fraction), height: thickness)
                Circle().fill(fill).frame(width: knob, height: knob)
                    .offset(x: max(0, min(w - knob, w * fraction - knob / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard enabled, w > 0 else { return }
                let v = Int((min(max(0, g.location.x / w), 1) * 100).rounded())
                if v != store.snapshot.volume { store.setVolume(v) }
            })
        }
        .frame(height: max(knob, 14) + 6)
        .background(ScrollWheelReader { delta, precise in
            guard enabled else { return }
            let steps = scroll.steps(for: delta, precise: precise)
            if steps != 0 { store.adjustVolume(by: steps) }
        })
        .focusable(enabled)
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            guard enabled else { return .ignored }
            store.adjustVolume(by: press.key == .upArrow || press.key == .rightArrow ? 2 : -2)
            return .handled
        }
        .opacity(enabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(snap.volume) %")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: store.adjustVolume(by: 2)
            case .decrement: store.adjustVolume(by: -2)
            @unknown default: break
            }
        }
    }
}
