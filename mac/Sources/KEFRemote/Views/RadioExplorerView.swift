import KEFKit
import SwiftUI

// Explorateur de radios (designs Classique, Hi-Fi, Immersif, Éditorial) : panneau qui
// recouvre la fenêtre sous la barre de titre. Accueil (Pays / Genres / Langues + étagères),
// listes empilées avec fil d'Ariane, raffinements en puces, stations paginées.

// MARK: - Habillage selon le design

/// Couleurs, formes et typographie de l'explorateur, dérivées du design courant. Les
/// éléments colorés suivent la palette « années 80 » (`Synthwave`) dans tous les designs ;
/// chaque design garde sa typographie et ses formes.
struct ExplorerSkin {
    let design: AppDesign
    let dark: Bool

    init(_ theme: DesignTheme, scheme: ColorScheme) {
        design = theme.design
        dark = scheme == .dark
    }

    var isPixel: Bool { design == .pixel }
    var isNeon: Bool { design == .neon }
    private var pixel: PixelPalette { PixelPalette(dark: dark) }

    var text: Color {
        switch design {
        case .hifi: HiFiPalette.text
        case .editorial: EditorialPalette.ink
        case .immersif: .white
        case .pixel: pixel.text
        case .neon: NeonPalette(dark: dark).text
        default: .primary
        }
    }

    var secondary: Color {
        switch design {
        case .hifi: HiFiPalette.secondary
        case .editorial: EditorialPalette.muted
        case .immersif: .white.opacity(0.65)
        case .pixel: pixel.secondary
        case .neon: NeonPalette(dark: dark).secondary
        default: .secondary
        }
    }

    var rule: Color {
        switch design {
        case .hifi: HiFiPalette.edge
        case .editorial: EditorialPalette.rule
        case .immersif: .white.opacity(0.14)
        case .pixel: pixel.ink
        case .neon: dark ? Color(Synthwave.magenta).opacity(0.45) : Color(Synthwave.violet).opacity(0.2)
        default: dark ? Color(Synthwave.violet).opacity(0.35) : Color(Synthwave.plum).opacity(0.14)
        }
    }

    /// Accent : néon cyan la nuit, rose soutenu le jour (contraste suffisant pour du texte).
    var accent: Color {
        switch design {
        case .hifi: Color(Synthwave.sun)
        case .editorial: EditorialPalette.orange
        case .immersif: .white
        case .pixel: pixel.accent
        default: dark ? Color(Synthwave.cyan) : Color(hex: 0xC8156E)
        }
    }

    var radius: CGFloat {
        switch design {
        case .hifi: 3
        case .editorial, .pixel: 0
        case .immersif: 14
        case .neon: 10
        default: 12
        }
    }

    var fontDesign: Font.Design { design == .hifi || isPixel ? .monospaced : .default }

    /// Graisse des lignes de liste (monospace gras en pixel, plus lisible que la police bitmap).
    var rowWeight: Font.Weight { isPixel ? .bold : .regular }

    /// Fond d'une carte / ligne.
    var card: AnyShapeStyle {
        switch design {
        case .hifi: AnyShapeStyle(HiFiPalette.panel)
        case .editorial: AnyShapeStyle(Color.clear)
        case .immersif: AnyShapeStyle(Color.white.opacity(0.08))
        case .pixel: AnyShapeStyle(pixel.card)
        case .neon: AnyShapeStyle(dark ? Color(Synthwave.night).opacity(0.75) : Color.white.opacity(0.72))
        default: AnyShapeStyle(dark ? Color.white.opacity(0.06) : Color.white.opacity(0.6))
        }
    }

    /// Tuiles colorées (genres, entrées) dans tous les designs.
    var colorfulTiles: Bool { true }

    /// Texte sur une tuile : blanc sur les dégradés ; en pixel (aplats), encre sombre sauf
    /// sur les teintes foncées.
    func tileText(_ pair: Synthwave.Pair) -> Color {
        guard isPixel else { return .white }
        return pair.start.contrastRatio(with: .white) > 4.5 ? .white : pixel.ink
    }

    func tileGradient(_ pair: Synthwave.Pair) -> AnyShapeStyle {
        if isPixel { return AnyShapeStyle(Color(pair.start)) }
        // Clair en haut à droite (pictogramme), sombre en bas à gauche (titre en blanc).
        return AnyShapeStyle(LinearGradient(colors: [Color(pair.start), Color(pair.end)],
                                            startPoint: .topTrailing, endPoint: .bottomLeading))
    }

    /// Halo néon autour d'une tuile.
    func glow(_ pair: Synthwave.Pair) -> Color {
        switch design {
        case .pixel: .clear
        case .hifi, .editorial: Color(pair.start).opacity(0.25)
        case .neon: Color(pair.start).opacity(dark ? 0.75 : 0.4)
        default: Color(pair.start).opacity(dark ? 0.5 : 0.3)
        }
    }

    func titleFont(_ size: CGFloat) -> Font {
        switch design {
        case .editorial: .system(size: size + 4, weight: .heavy)
        case .hifi: .system(size: size - 3, weight: .bold, design: .monospaced)
        case .pixel: .system(size: size - 4, weight: .heavy, design: .monospaced)
        case .neon: .system(size: size + 2, weight: .black).italic().width(.condensed)
        default: .system(size: size, weight: .bold)
        }
    }

    /// Libellé de section (capitales espacées).
    func sectionFont() -> Font { .system(size: 11, weight: .semibold, design: fontDesign) }

    @ViewBuilder func background() -> some View {
        switch design {
        case .hifi: BrushedMetal()
        case .editorial: EditorialPalette.paper
        case .immersif:
            // Opaque : le lecteur dessous ne doit pas se lire à travers.
            LinearGradient(colors: [Color(Synthwave.indigo), Color(Synthwave.night)], startPoint: .top, endPoint: .bottom)
        case .pixel: pixel.bg
        case .neon: NeonExplorerBackground(dark: dark)
        default:
            if dark {
                // Nuit indigo, lueur magenta à l'horizon (en bas).
                ZStack {
                    LinearGradient(colors: [Color(Synthwave.night), Color(Synthwave.indigo)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(Synthwave.magenta).opacity(0.22), .clear],
                                   center: .bottom, startRadius: 0, endRadius: 520)
                }
            } else {
                // Pastel de coucher de soleil.
                LinearGradient(colors: [Color(hex: 0xFFF3EA), Color(hex: 0xFDE6EF), Color(hex: 0xEFE3FB)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// Logo de station (pixelisé en design pixel).
    @MainActor @ViewBuilder func logo(_ station: Station, size: CGFloat, cornerRadius: CGFloat) -> some View {
        if isPixel {
            let unit: CGFloat = size >= 60 ? 4 : 2
            PixelThumb(source: station.icon, title: station.title, side: max(4, Int(size / unit) - 2), unit: unit)
        } else {
            StationLogo(station: station, cornerRadius: cornerRadius)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Bouton d'ouverture

/// « Explorer » : ouvre l'explorateur de radios (en-têtes des sections radios).
struct ExplorerButton: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 15
    var showsLabel = false

    var body: some View {
        Button { model.toggleExplorer() } label: {
            if showsLabel {
                Label("Explorer", systemImage: "safari").font(.system(size: size * 0.85, weight: .medium))
            } else {
                Image(systemName: "safari").font(.system(size: size))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Explorer les radios par pays, genre et langue (⌘E)")
        .accessibilityLabel("Explorer les radios")
    }
}

// MARK: - Panneau

struct RadioExplorerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.designTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let skin = ExplorerSkin(theme, scheme: scheme)
        let explorer = model.explorer
        VStack(spacing: 0) {
            ExplorerHeader(skin: skin)
            Rectangle().fill(skin.rule).frame(height: 1)
            ZStack {
                if let page = explorer.current {
                    ExplorerPageView(page: page, skin: skin)
                        .id(page.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                } else {
                    ExplorerHome(skin: skin)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(skin.background().ignoresSafeArea())
        .foregroundStyle(skin.text)
        .fontDesign(skin.fontDesign)
        .animation(.easeInOut(duration: 0.22), value: explorer.stack.map(\.id))
        .background {
            // Échap : liste précédente, puis fermeture.
            Button("") { back() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func back() {
        if model.explorer.isHome { model.toggleExplorer() } else { model.explorer.pop() }
    }
}

/// Retour, fil d'Ariane, fermeture.
private struct ExplorerHeader: View {
    @Environment(AppModel.self) private var model
    let skin: ExplorerSkin

    var body: some View {
        let explorer = model.explorer
        HStack(spacing: 10) {
            Button { explorer.pop() } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(explorer.isHome)
            .opacity(explorer.isHome ? 0.3 : 1)
            .help("Retour (Échap)")
            .accessibilityLabel("Retour")

            breadcrumb
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { model.toggleExplorer() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26)
                    .background(Circle().fill(skin.text.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Fermer l'explorateur (⌘E)")
            .accessibilityLabel("Fermer l'explorateur")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    /// « Radios › Genres › Jazz » ; au-delà de trois niveaux, le milieu est replié (…).
    private var breadcrumb: some View {
        let explorer = model.explorer
        let stack = explorer.stack
        let shown: [RadioExplorerPage?] = stack.count > 3 ? [stack[0], nil] + stack.suffix(2) : stack
        return HStack(spacing: 5) {
            crumb("Radios", current: stack.isEmpty) { explorer.popToRoot() }
                .layoutPriority(stack.isEmpty ? 1 : 0)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, page in
                Image(systemName: "chevron.compact.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(skin.secondary)
                if let page {
                    crumb(page.title, current: page === explorer.current) { explorer.pop(to: page) }
                        .layoutPriority(page === explorer.current ? 1 : 0)
                } else {
                    Text("…").foregroundStyle(skin.secondary)
                }
            }
        }
        .font(.system(size: 13, weight: .medium, design: skin.fontDesign))
        .lineLimit(1)
    }

    private func crumb(_ title: String, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(skin.design == .hifi ? title.uppercased() : title)
                .fontWeight(current ? .bold : .medium)
                .foregroundStyle(current ? skin.text : skin.secondary)
                .truncationMode(.tail)
        }
        .buttonStyle(.plain)
        .disabled(current)
    }
}

// MARK: - Accueil

private struct ExplorerHome: View {
    @Environment(AppModel.self) private var model
    let skin: ExplorerSkin

    var body: some View {
        let explorer = model.explorer
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    if skin.isPixel {
                        PixelTitle(text: "Explorer les radios", color: skin.text)
                    } else if skin.isNeon {
                        ChromeText(text: "Explorer les radios", size: 30, alignment: .leading)
                            .padding(.leading, -4)
                    } else {
                        Text("Explorer les radios").font(skin.titleFont(24))
                    }
                    Text("Des milliers de stations airable, par pays, par genre ou par langue.")
                        .font(.callout).foregroundStyle(skin.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Array(RadioDirectory.filters.enumerated()), id: \.element) { index, directory in
                        Button { explorer.open(directory) } label: {
                            EntryTile(title: directory.title, subtitle: directory.subtitle, symbol: directory.symbol,
                                      pair: Synthwave.entryPair(index), scene: Synthwave.entryScene(index),
                                      skin: skin, height: 96)
                        }
                        .buttonStyle(TilePressStyle())
                        .accessibilityLabel("\(directory.title) : \(directory.subtitle)")
                    }
                }
                ForEach([RadioDirectory.popular, .trending]) { directory in
                    ShelfStrip(directory: directory, skin: skin)
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Plus d'étagères", skin: skin)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(RadioDirectory.shelves.filter { $0 != .popular && $0 != .trending }) { directory in
                            Button { explorer.open(directory) } label: {
                                ShelfCard(directory: directory, skin: skin)
                            }
                            .buttonStyle(TilePressStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.automatic)
    }
}

private struct SectionLabel: View {
    let text: String
    let skin: ExplorerSkin
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if skin.isPixel {
                PixelText(text: text, scale: 2, color: skin.secondary)
            } else {
                Text(text.uppercased()).font(skin.sectionFont()).tracking(1.2).foregroundStyle(skin.secondary)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(skin.secondary)
            }
        }
    }
}

/// Grande tuile d'entrée (Pays, Genres, Langues) ou de genre : dégradé de la palette
/// « années 80 », ou petite scène (soleil rayé, grille) pour les entrées de l'accueil.
private struct EntryTile: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let pair: Synthwave.Pair
    var scene: Synthwave.Scene?
    let skin: ExplorerSkin
    var height: CGFloat = 74

    var body: some View {
        let ink = skin.tileText(pair)
        let shape = RoundedRectangle(cornerRadius: skin.radius, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            if scene == nil {
                Image(systemName: symbol)
                    .font(.system(size: height * 0.5, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.28))
                    .rotationEffect(.degrees(-12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, height * 0.1)
                    .padding(.trailing, height * 0.12)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(skin.design == .hifi || skin.isPixel ? title.uppercased() : title)
                    .font(.system(size: height > 90 ? 18 : 14, weight: skin.isPixel ? .heavy : .bold, design: skin.fontDesign))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle).font(.caption.weight(.medium)).lineLimit(1)
                        .foregroundStyle(ink.opacity(0.85))
                }
            }
            .foregroundStyle(ink)
            .shadow(color: ink == .white ? Color(Synthwave.night).opacity(0.55) : .clear, radius: 2, y: 1)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            if skin.isPixel {
                // Aplat, contour épais, ombre portée franche.
                Rectangle().fill(skin.rule).offset(x: 3, y: 3)
                Rectangle().fill(skin.tileGradient(pair))
                Rectangle().strokeBorder(skin.rule, lineWidth: 2)
            } else if let scene {
                SynthwaveArtView(scene: scene, showsPalms: false)
                    .overlay {
                        // Voile nocturne sous le titre.
                        LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                               .init(color: Color(Synthwave.night).opacity(0.75), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .clipShape(shape)
                    .shadow(color: skin.glow(pair), radius: 9)
                shape.strokeBorder(Color(scene.sky.horizon).opacity(0.7), lineWidth: 1)
            } else {
                shape.fill(skin.tileGradient(pair))
                    .shadow(color: skin.glow(pair), radius: 7)
                shape.strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
        }
        .contentShape(shape)
    }
}

/// Carte compacte d'une étagère (pictogramme + titre).
private struct ShelfCard: View {
    let directory: RadioDirectory
    let skin: ExplorerSkin

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: directory.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(skin.tileText(Synthwave.pair(forKey: directory.title)))
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: skin.radius * 0.6, style: .continuous)
                        .fill(skin.tileGradient(Synthwave.pair(forKey: directory.title)))
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(skin.design == .hifi ? directory.title.uppercased() : directory.title)
                    .font(.system(size: 13, weight: .semibold, design: skin.fontDesign)).lineLimit(1)
                Text(directory.subtitle).font(.caption).foregroundStyle(skin.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(skin.secondary)
        }
        .padding(8)
        .background {
            let shape = RoundedRectangle(cornerRadius: skin.radius, style: .continuous)
            shape.fill(skin.card)
            if skin.design == .editorial || skin.design == .hifi || skin.isPixel {
                shape.strokeBorder(skin.rule, lineWidth: skin.isPixel ? 2 : 1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Aperçu horizontal d'une étagère (logos), « Tout voir ».
private struct ShelfStrip: View {
    @Environment(AppModel.self) private var model
    let directory: RadioDirectory
    let skin: ExplorerSkin

    var body: some View {
        let explorer = model.explorer
        let page = explorer.shelves[directory]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: directory.title, skin: skin)
                Button("Tout voir") { explorer.open(directory) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(skin.accent)
                    .fixedSize()
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    if let page, page.state == .loaded {
                        ForEach(page.stations.prefix(16)) { station in
                            StationCard(station: station, skin: skin)
                        }
                    } else if case .failed(let message) = page?.state {
                        Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(skin.secondary)
                            .frame(height: 100)
                        Button("Réessayer") { if let page { explorer.retry(page) } }.controlSize(.small)
                    } else {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: skin.radius, style: .continuous).fill(skin.card)
                                .frame(width: 84, height: 84)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
        }
    }
}

/// Logo + nom (aperçus d'étagère) : clic = lecture, étoile en coin.
private struct StationCard: View {
    @Environment(AppModel.self) private var model
    let station: Station
    let skin: ExplorerSkin
    @State private var hovering = false

    var body: some View {
        let current = model.isCurrent(station)
        let favorite = model.favorites.contains(station)
        VStack(spacing: 6) {
            skin.logo(station, size: 84, cornerRadius: max(2, skin.radius))
                .overlay {
                    if model.store.loadingStationID == station.id {
                        RoundedRectangle(cornerRadius: skin.radius, style: .continuous).fill(.black.opacity(0.35))
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if favorite || hovering {
                        FavoriteStar(station: station, size: 11, skin: skin, badge: true)
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if current {
                        EqualizerBars(animating: model.store.snapshot.isPlaying)
                            .padding(4).background(Circle().fill(skin.accent == .white ? Color(Synthwave.hotPink) : skin.accent)).padding(4)
                    }
                }
                .scaleEffect(hovering ? 1.04 : 1)
            Text(station.title)
                .font(.caption.weight(current ? .semibold : .regular))
                .foregroundStyle(current ? skin.accent : skin.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 88)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.play(station) }
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .help(station.description ?? station.title)
        .contextMenu { StationContextMenu(station: station) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(station.title + (favorite ? ", favori" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: favorite ? "Retirer des favoris" : "Ajouter aux favoris") { model.toggleFavorite(station) }
    }
}

private struct StationContextMenu: View {
    @Environment(AppModel.self) private var model
    let station: Station

    var body: some View {
        Button("Lire") { model.play(station) }
        Button(model.favorites.contains(station) ? "Retirer des favoris" : "Ajouter aux favoris") {
            model.toggleFavorite(station)
        }
    }
}

/// Étoile favori : pleine si la station est déjà dans les favoris.
private struct FavoriteStar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.designTheme) private var theme
    let station: Station
    var size: CGFloat = 14
    let skin: ExplorerSkin
    /// Sur un logo : pastille sombre pour rester lisible.
    var badge = false

    var body: some View {
        let on = model.favorites.contains(station)
        Button { model.toggleFavorite(station) } label: {
            Group {
                if skin.isPixel {
                    // Étoile bitmap : remplie (favori) ou creuse.
                    PixelIconView(icon: .star, scale: 2, ink: PixelPalette(dark: skin.dark).ink,
                                  fill: on ? PixelPalette(dark: skin.dark).mustard : (badge ? PixelPalette(dark: skin.dark).card : nil))
                } else {
                    Image(systemName: on ? "star.fill" : "star")
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(on ? theme.favorite : (badge ? Color.white : skin.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size + (badge ? 9 : 12), height: size + (badge ? 9 : 12))
            .background {
                if badge && !skin.isPixel { Circle().fill(.black.opacity(0.5)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "Retirer « \(station.title) » des favoris" : "Ajouter « \(station.title) » aux favoris")
        .accessibilityLabel(on ? "Retirer \(station.title) des favoris" : "Ajouter \(station.title) aux favoris")
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Liste

private struct ExplorerPageView: View {
    @Environment(AppModel.self) private var model
    @Bindable var page: RadioExplorerPage
    let skin: ExplorerSkin

    var body: some View {
        let firstLoad = (page.state == .idle || page.state == .loading) && page.items.isEmpty && page.refinements.isEmpty
        switch page.state {
        case _ where firstLoad:
            VStack(spacing: 10) {
                ProgressView()
                Text("Chargement…").font(.callout).foregroundStyle(skin.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            placeholder(symbol: "wifi.exclamationmark", title: "Liste indisponible", message: message) {
                Button("Réessayer") { model.explorer.retry(page) }
                    .keyboardShortcut(.defaultAction)
            }
        default:
            content
        }
    }

    private var content: some View {
        let items = page.filteredItems
        let folders = items.filter(\.isFolder)
        let stations = items.filter { $0.station != nil }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                header
                    .padding(.bottom, 12)
                if !page.refinements.isEmpty {
                    RefinementChips(page: page, skin: skin)
                        .padding(.bottom, 12)
                }
                if page.items.count > 8 {
                    SearchField(text: $page.filterText, isSearching: false,
                                prompt: page.stations.isEmpty ? "Filtrer la liste" : "Filtrer les \(page.stations.count) stations chargées")
                        .padding(.bottom, 12)
                }
                if !folders.isEmpty {
                    if page.style == .genres {
                        GenreGrid(folders: folders, skin: skin)
                            .padding(.bottom, 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(folders) { FolderRow(item: $0, style: page.style, skin: skin) }
                        }
                        .padding(.bottom, 16)
                    }
                }
                if !stations.isEmpty && !folders.isEmpty {
                    SectionLabel(text: "Stations", skin: skin).padding(.bottom, 6)
                }
                ForEach(stations) { item in
                    if let station = item.station {
                        ExplorerStationRow(station: station, skin: skin)
                            .onAppear {
                                // Chargement au défilement : à l'approche de la fin de ce qui est chargé.
                                if page.filterText.isEmpty, item.id == stations.last?.id { model.explorer.loadMore(page) }
                            }
                    }
                }
                footer(isEmpty: items.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.automatic)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            if skin.isPixel {
                PixelTitle(text: page.headerTitle, color: skin.text)
            } else if skin.isNeon {
                ChromeText(text: page.headerTitle, size: 28, alignment: .leading)
                    .padding(.leading, -4)
            } else {
                Text(skin.design == .hifi ? page.headerTitle.uppercased() : page.headerTitle)
                    .font(skin.titleFont(24))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(skin.secondary).lineLimit(1)
            }
        }
    }

    /// « Région: Europe · 53 entrées », « 2 059 stations »…
    private var subtitle: String? {
        var parts: [String] = []
        // Liste « Tout de: Jazz » : l'en-tête dit « Jazz », le sous-titre « Toutes les stations ».
        if page.scope != nil { parts.append(RadioExplorerModel.allStationsTitle) }
        if let t = page.listTitle, t != "Filtre", t.lowercased() != page.headerTitle.lowercased(), !t.hasSuffix(page.headerTitle) {
            parts.append(t.replacingOccurrences(of: ": ", with: " : "))
        }
        if let n = page.announcedCount, n > 0 {
            let noun = page.stations.isEmpty && !page.folders.isEmpty ? "entrée" : "station"
            parts.append("\(n.formatted()) \(noun)\(n > 1 ? "s" : "")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func footer(isEmpty: Bool) -> some View {
        Group {
            if page.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Chargement des stations suivantes…").font(.caption).foregroundStyle(skin.secondary)
                }
            } else if let error = page.loadMoreError {
                HStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(skin.secondary)
                    Button("Réessayer") { model.explorer.retry(page) }.controlSize(.small)
                }
            } else if isEmpty {
                if page.filterText.isEmpty {
                    placeholder(symbol: "dot.radiowaves.left.and.right", title: "Aucune station",
                                message: "Cette liste est vide pour le moment.") { EmptyView() }
                        .frame(height: 220)
                } else {
                    placeholder(symbol: "magnifyingglass", title: "Aucun résultat",
                                message: page.hasMore ? "Rien parmi les stations chargées. Faites défiler ou effacez le filtre."
                                                      : "Aucune entrée ne contient « \(page.filterText) ».") {
                        if page.hasMore {
                            Button("Charger plus de stations") { model.explorer.loadMore(page) }
                        }
                    }
                    .frame(height: 220)
                }
            } else if page.hasMore && !page.filterText.isEmpty {
                Button("Charger plus de stations") { model.explorer.loadMore(page) }.controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func placeholder<Action: View>(symbol: String, title: String, message: String,
                                           @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(skin.secondary)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(skin.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            action()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// « Affiner : Pays · Langue · Genre » (raffinements de la liste filtrée).
private struct RefinementChips: View {
    @Environment(AppModel.self) private var model
    let page: RadioExplorerPage
    let skin: ExplorerSkin

    var body: some View {
        HStack(spacing: 8) {
            Text("Affiner").font(.caption.weight(.semibold)).foregroundStyle(skin.secondary)
                .fixedSize()
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(page.refinements) { item in
                        chip(item)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
        }
    }

    private func chip(_ item: RadioBrowseItem) -> some View {
        let facet = item.facet ?? .genre
        let active = item.activeValue
        let shape = RoundedRectangle(cornerRadius: skin.radius == 0 ? 0 : 20, style: .continuous)
        return Button { model.explorer.open(item) } label: {
            HStack(spacing: 5) {
                Image(systemName: facet.symbol).font(.system(size: 11, weight: .semibold))
                Text(active.map { "\(facet.label) : \($0)" } ?? "Par \(facet.label.lowercased())")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
            }
            .font(.system(size: 12, weight: .medium, design: skin.fontDesign))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(active != nil ? skin.accent : skin.text)
            .background(shape.fill(active != nil ? AnyShapeStyle(skin.accent.opacity(0.14)) : skin.card))
            .overlay(shape.strokeBorder(active != nil ? skin.accent.opacity(0.6) : skin.rule, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(active.map { "Filtre \(facet.label.lowercased()) : \($0) — changer" } ?? "Affiner par \(facet.label.lowercased())")
    }
}

/// Genres et sous-genres : tuiles colorées.
private struct GenreGrid: View {
    @Environment(AppModel.self) private var model
    let folders: [RadioBrowseItem]
    let skin: ExplorerSkin

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
            ForEach(folders) { item in
                let style = RadioCatalog.genreStyle(for: item.displayTitle)
                Button { model.explorer.open(item) } label: {
                    EntryTile(title: item.isAllOf ? "Tout \(item.displayTitle)" : item.title,
                              subtitle: item.isAllOf ? "Toutes les stations" : nil,
                              symbol: item.isAllOf ? "square.grid.2x2.fill" : style.symbol,
                              pair: Synthwave.genrePair(for: item.displayTitle),
                              scene: item.isAllOf ? Synthwave.scene(forKey: item.displayTitle) : nil, skin: skin)
                }
                .buttonStyle(TilePressStyle())
                .accessibilityLabel(item.isAllOf ? "Toutes les stations \(item.displayTitle)" : item.title)
            }
        }
    }
}

/// Dossier (région, pays, ville, langue…) : drapeau, globe ou pastille de langue.
private struct FolderRow: View {
    @Environment(AppModel.self) private var model
    let item: RadioBrowseItem
    let style: RadioExplorerStyle
    let skin: ExplorerSkin
    @State private var hovering = false

    var body: some View {
        Button { model.explorer.open(item) } label: {
            HStack(spacing: 12) {
                icon.frame(width: 32, height: 32)
                Text(item.isAllOf ? "Toutes les stations · \(item.displayTitle)" : item.title)
                    .font(.system(size: 14, weight: item.isAllOf ? .semibold : skin.rowWeight, design: skin.fontDesign))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(skin.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: max(2, skin.radius * 0.7), style: .continuous)
                .fill(hovering ? skin.text.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) { Rectangle().fill(skin.rule.opacity(0.6)).frame(height: 0.5).padding(.leading, 52) }
    }

    @ViewBuilder private var icon: some View {
        let name = item.displayTitle
        if item.isAllOf {
            symbolBadge("dot.radiowaves.left.and.right")
        } else if style == .countries, let flag = RadioCatalog.flag(forCountry: name) {
            Text(flag).font(.system(size: 24))
        } else if style == .countries, let globe = RadioCatalog.regionSymbol(forName: name) {
            symbolBadge(globe)
        } else if style == .languages, let code = RadioCatalog.languageBadge(forName: name) {
            Text(code)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(skin.tileText(Synthwave.pair(forKey: code)))
                .frame(width: 30, height: 30)
                .background {
                    let shape = RoundedRectangle(cornerRadius: max(2, skin.radius * 0.6), style: .continuous)
                    shape.fill(skin.tileGradient(Synthwave.pair(forKey: code)))
                    if skin.isPixel { shape.strokeBorder(skin.rule, lineWidth: 2) }
                }
        } else if style == .genres {
            symbolBadge(RadioCatalog.genreStyle(for: name).symbol)
        } else {
            symbolBadge(style == .countries ? "mappin.circle.fill" : "folder.fill")
        }
    }

    private func symbolBadge(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(skin.accent)
    }
}

/// Station : logo, nom, clic = lecture, étoile favori, indicateur de lecture.
private struct ExplorerStationRow: View {
    @Environment(AppModel.self) private var model
    let station: Station
    let skin: ExplorerSkin
    @State private var hovering = false

    var body: some View {
        let current = model.isCurrent(station)
        HStack(spacing: 12) {
            skin.logo(station, size: 38, cornerRadius: max(2, skin.radius * 0.6))
                .overlay {
                    if hovering && !current {
                        RoundedRectangle(cornerRadius: max(2, skin.radius * 0.6), style: .continuous).fill(.black.opacity(0.35))
                        Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(.white)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(station.title)
                    .font(.system(size: 14, weight: current ? .heavy : skin.rowWeight, design: skin.fontDesign))
                    .foregroundStyle(current ? skin.accent : skin.text)
                    .lineLimit(1)
                if let d = station.description {
                    Text(d).font(.caption).foregroundStyle(skin.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if model.store.loadingStationID == station.id {
                ProgressView().controlSize(.small)
            } else if current {
                EqualizerBars(animating: model.store.snapshot.isPlaying, color: skin.accent)
            }
            FavoriteStar(station: station, skin: skin)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: max(2, skin.radius * 0.7), style: .continuous)
            .fill(current ? skin.accent.opacity(0.12) : (hovering ? skin.text.opacity(0.06) : .clear)))
        .contentShape(Rectangle())
        .onTapGesture { model.play(station) }
        .onHover { hovering = $0 }
        .contextMenu { StationContextMenu(station: station) }
        .help("Lire « \(station.title) »")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.play(station) }
    }
}
