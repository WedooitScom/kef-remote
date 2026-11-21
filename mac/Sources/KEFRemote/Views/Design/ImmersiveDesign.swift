import KEFKit
import SwiftUI

// Design « Pochette immersive » : la pochette floutée couvre toute la fenêtre, le contenu
// tient en une seule colonne centrée (pochette nette, très grand titre, transport), les
// sources sont de petites icônes dans une barre supérieure translucide et les favoris une
// rangée de pastilles en bas. En veille : fond ambiant animé et grand bouton marche.

// MARK: - Fond

/// Fond plein cadre : pochette très floutée et assombrie, voile de sa couleur dominante
/// en dégradé vers le bas ; sans pochette (veille, entrée physique…), fond ambiant animé
/// dans les teintes de `ambientSeed` (dernier visuel connu, sinon premier favori).
struct ImmersiveBackdrop: View {
    let cover: String?
    let ambientSeed: String?
    @State private var tint = DominantColor.fallback
    @State private var layer: BlurLayer?

    /// Image floutée affichée, identifiée par sa source (fondu enchaîné au changement).
    private struct BlurLayer: Equatable {
        let source: String
        let image: CGImage
        static func == (a: Self, b: Self) -> Bool { a.source == b.source }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AmbientField(base: tint, animated: cover == nil)
                if let layer {
                    ZStack {
                        Image(decorative: layer.image, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(1.15)
                            .saturation(1.2)
                        Color.black.opacity(0.24)
                        LinearGradient(stops: [
                            .init(color: Color(tint).opacity(0.10), location: 0),
                            .init(color: Color(tint).opacity(0.45), location: 0.55),
                            .init(color: Color(tint).opacity(0.92), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .id(layer.source)
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: cover ?? ambientSeed) {
            let next = await CoverColors.shared.color(for: cover ?? ambientSeed)
            let image = await CoverColors.shared.blurredImage(for: cover)
            withAnimation(.easeInOut(duration: 0.9)) {
                tint = next
                if let cover, let image { layer = BlurLayer(source: cover, image: image) } else { layer = nil }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Dégradé maillé (macOS 15+) ou dégradés radiaux (macOS 14) qui dérivent lentement,
/// dans des teintes voisines de `base`. Figé si « Réduire les animations ».
private struct AmbientField: View {
    let base: SRGBColor
    var animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = Self.palette(from: base)
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if #available(macOS 15.0, *) {
                    MeshGradient(width: 3, height: 3, points: Self.meshPoints(t), colors: [
                        palette[1], palette[0], palette[2],
                        palette[2], palette[1], palette[0],
                        palette[3], palette[3], palette[3],
                    ])
                } else {
                    palette[3]
                    RadialGradient(colors: [palette[0], .clear], center: Self.drift(t, 0.07, 0.3, 0.25),
                                   startRadius: 0, endRadius: 520)
                    RadialGradient(colors: [palette[2], .clear], center: Self.drift(t, 0.05, 0.75, 0.35),
                                   startRadius: 0, endRadius: 460)
                    RadialGradient(colors: [palette[1].opacity(0.8), .clear], center: Self.drift(t, 0.04, 0.5, 0.7),
                                   startRadius: 0, endRadius: 420)
                }
                // Bas plus sombre : contraste des pastilles de favoris.
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: base)
    }

    /// Quatre teintes : vive, voisine chaude, voisine froide, fond presque noir.
    static func palette(from color: SRGBColor) -> [Color] {
        var (h, s, _) = color.hsb
        if s < 0.12 { h = 0.055; s = 0.6 } // pas de teinte exploitable : cuivre KEF
        s = min(0.85, max(s, 0.55))
        return [
            Color(SRGBColor(hue: h, saturation: s, brightness: 0.52)),
            Color(SRGBColor(hue: h + 0.07, saturation: s * 0.85, brightness: 0.34)),
            Color(SRGBColor(hue: h - 0.08, saturation: s, brightness: 0.26)),
            Color(SRGBColor(hue: h, saturation: s * 0.7, brightness: 0.07)),
        ]
    }

    /// Points du maillage 3 × 3 : bords fixes, milieu et arêtes qui ondulent.
    static func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func w(_ speed: Double, _ phase: Double, _ amp: Double) -> Float { Float(sin(t * speed + phase) * amp) }
        return [
            [0, 0], [0.5 + w(0.11, 0, 0.18), 0], [1, 0],
            [0, 0.45 + w(0.09, 1, 0.15)], [0.5 + w(0.07, 2, 0.2), 0.45 + w(0.13, 3, 0.15)], [1, 0.5 + w(0.1, 4, 0.15)],
            [0, 1], [0.5 + w(0.08, 5, 0.2), 1], [1, 1],
        ]
    }

    static func drift(_ t: Double, _ speed: Double, _ x: Double, _ y: Double) -> UnitPoint {
        UnitPoint(x: x + sin(t * speed) * 0.18, y: y + cos(t * speed * 1.3) * 0.14)
    }
}

/// Dernier visuel connu, pour teinter le fond ambiant de la veille : celui de la session,
/// sinon celui mémorisé (UserDefaults, jamais en démo), sinon le premier favori ou la
/// première suggestion.
@MainActor
private enum AmbientSeed {
    static let storageKey = "immersiveLastCover"
    private static var session: String?

    static func remember(_ cover: String?, model: AppModel, stored: inout String) {
        guard let cover else { return }
        session = cover
        if !model.isDemo, stored != cover { stored = cover }
    }

    static func resolve(_ model: AppModel, stored: String) -> String? {
        if let cover = NowPlayingText.cover(model) { return cover }
        if let session { return session }
        if !stored.isEmpty, !model.isDemo { return stored }
        return model.favorites.items.first?.icon ?? model.history.first?.icon
    }
}

// MARK: - Commandes

/// Grand bouton lecture rond blanc et boutons précédent / suivant.
private struct ImmersiveTransport: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 68

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let canControl = store.status.isOnline && snap.isOn
        let previous = model.skipPlan(.previous), next = model.skipPlan(.next)
        HStack(spacing: size * 0.45) {
            Button { model.skip(.previous) } label: {
                Image(systemName: "backward.fill").font(.system(size: size * 0.3, weight: .semibold))
                    .frame(width: size * 0.7, height: size * 0.7).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(previous.isEnabled ? 0.9 : 0.3)
            .disabled(!previous.isEnabled)
            .help(previous.help)
            .accessibilityLabel(previous.label)

            Button { Task { await store.playPause() } } label: {
                Image(systemName: snap.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: snap.isPlaying ? 0 : size * 0.03)
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: size, height: size)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.35), radius: size * 0.2, y: size * 0.08)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .opacity(canControl ? 1 : 0.4)
            .disabled(!canControl)
            .help(PlayPauseText.help(snap))
            .accessibilityLabel(PlayPauseText.label(snap))

            Button { model.skip(.next) } label: {
                Image(systemName: "forward.fill").font(.system(size: size * 0.3, weight: .semibold))
                    .frame(width: size * 0.7, height: size * 0.7).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(next.isEnabled ? 0.9 : 0.3)
            .disabled(!next.isEnabled)
            .help(next.help)
            .accessibilityLabel(next.label)
        }
        .foregroundStyle(.white)
    }
}

/// Léger enfoncement au clic.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Barre de progression fine (ou « EN DIRECT » pour une radio).
private struct ImmersiveProgress: View {
    let store: SpeakerStore
    var showTimes = true

    var body: some View {
        let snap = store.snapshot
        if let duration = snap.player.durationMs, !snap.player.isLive, snap.isOn {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let position = store.estimatedPosition(at: context.date) ?? 0
                let fraction = duration > 0 ? min(1, Double(position) / Double(duration)) : 0
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            Capsule().fill(.white).frame(width: max(2, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 2)
                    if showTimes {
                        HStack {
                            Text(formatTime(position))
                            Spacer()
                            Text("-" + formatTime(max(0, duration - position)))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Progression")
        } else if snap.player.isLive && snap.isPlaying {
            HStack(spacing: 6) {
                EqualizerBars(animating: true, color: .white)
                Text("EN DIRECT").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// Volume : haut-parleur (sourdine), filet, valeur.
private struct ImmersiveVolume: View {
    let store: SpeakerStore
    var knob: CGFloat = 11

    var body: some View {
        let snap = store.snapshot
        HStack(spacing: 10) {
            Button { store.toggleMute() } label: {
                Image(systemName: snap.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .frame(width: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(snap.isMuted ? "Rétablir le son" : "Couper le son")
            .accessibilityLabel(snap.isMuted ? "Rétablir le son" : "Couper le son")
            ThinVolumeSlider(store: store, track: .white.opacity(0.22), fill: .white, thickness: 2, knob: knob)
            Text(verbatim: "\(snap.volume)").font(.caption.monospacedDigit()).frame(width: 24, alignment: .trailing)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white.opacity(0.85))
        .disabled(!(store.status.isOnline && snap.isOn))
    }
}

/// Sources en petites icônes rondes (la source active en blanc).
private struct ImmersiveSourceIcons: View {
    let store: SpeakerStore
    var size: CGFloat = 28

    var body: some View {
        let snap = store.snapshot
        HStack(spacing: 2) {
            ForEach(snap.sources) { source in
                let selected = snap.isOn && snap.source == source
                Button { Task { await store.selectSource(source) } } label: {
                    Image(systemName: source.symbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .frame(width: size, height: size)
                        .foregroundStyle(selected ? Color.black.opacity(0.85) : .white.opacity(0.72))
                        .background(Circle().fill(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.clear)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .help(source.label)
                .accessibilityLabel("Source \(source.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .disabled(!store.status.isOnline)
        .opacity(store.status.isOnline ? 1 : 0.45)
        .animation(.easeOut(duration: 0.2), value: snap.source)
        .animation(.easeOut(duration: 0.2), value: snap.power)
    }
}

/// Bouton marche / veille rond (blanc quand allumée).
private struct ImmersivePowerButton: View {
    let store: SpeakerStore
    var size: CGFloat = 28

    var body: some View {
        let on = store.snapshot.isOn
        Button { Task { await store.togglePower() } } label: {
            Image(systemName: "power")
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(on ? Color.black.opacity(0.85) : .white)
                .background(Circle().fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.14))))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!store.status.isOnline)
        .opacity(store.status.isOnline ? 1 : 0.4)
        .help(on ? "Mettre en veille (⇧⌘P)" : "Allumer (⇧⌘P)")
        .accessibilityLabel(on ? "Mettre en veille" : "Allumer")
    }
}

/// Petit bouton icône blanc translucide (réglages, recherche…).
private struct GlassIconStyle: ButtonStyle {
    var size: CGFloat = 28
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.44, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(active ? Color.black.opacity(0.85) : .white.opacity(0.85))
            .background(Circle().fill(active ? AnyShapeStyle(.white)
                                             : AnyShapeStyle(.white.opacity(configuration.isPressed ? 0.24 : 0.1))))
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

// MARK: - Pastilles de favoris

/// Pastille de station : logo rond + nom ; station en cours en blanc.
private struct StationChip: View {
    @Environment(AppModel.self) private var model
    let station: Station
    var logoSize: CGFloat = 32
    var font: Font = .callout
    var maxTitleWidth: CGFloat = 150
    var highlighted = false

    var body: some View {
        let current = model.isCurrent(station)
        HStack(spacing: 8) {
            StationLogo(station: station, cornerRadius: logoSize / 2)
                .frame(width: logoSize, height: logoSize)
                .clipShape(Circle())
            Text(station.title)
                .font(font.weight(current ? .semibold : .medium))
                .lineLimit(1)
                .frame(maxWidth: maxTitleWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            if model.store.loadingStationID == station.id {
                ProgressView().controlSize(.mini)
            } else if current {
                EqualizerBars(animating: model.store.snapshot.isPlaying, color: .black.opacity(0.75))
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .foregroundStyle(current ? Color.black.opacity(0.85) : .white)
        .background {
            Capsule().fill(current ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.32)))
            if !current { Capsule().fill(.white.opacity(0.06)) }
        }
        .overlay {
            Capsule().strokeBorder(.white.opacity(current ? 0 : 0.14), lineWidth: 0.5)
            if highlighted {
                Capsule().strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).padding(-3)
            }
        }
        .contentShape(Capsule())
        .help(station.description ?? station.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StationAccessibility.label(station.title, current: current))
        .accessibilityAddTraits(.isButton)
    }
}

/// Rangée horizontale défilante : favoris (glisser-déposer, menu contextuel), sinon
/// suggestions de l'historique (« Tout ajouter »), sinon invitation à chercher.
private struct ImmersiveFavoritesStrip: View {
    @Environment(AppModel.self) private var model
    var compact = false
    var onSearch: () -> Void = {}
    @State private var dropTarget: String?

    var body: some View {
        let logo: CGFloat = compact ? 24 : 32
        let font: Font = compact ? .caption : .callout
        let titleWidth: CGFloat = compact ? 96 : 150
        if !model.favorites.items.isEmpty {
            strip {
                ForEach(Array(model.favorites.items.enumerated()), id: \.element.id) { index, station in
                    StationChip(station: station, logoSize: logo, font: font, maxTitleWidth: titleWidth,
                                highlighted: dropTarget == station.id)
                        .favoriteInteractions(station: station, index: index, dropTarget: $dropTarget)
                }
            }
            .animation(.spring(duration: 0.3), value: model.favorites.items)
        } else if model.favorites.suggestHistory && !model.history.isEmpty {
            HStack(spacing: 10) {
                if !compact {
                    Text("Récemment").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                }
                strip {
                    ForEach(model.history.prefix(12)) { station in
                        StationChip(station: station, logoSize: logo, font: font, maxTitleWidth: titleWidth)
                            .onTapGesture { model.play(station) }
                    }
                }
                Button("Tout ajouter") {
                    withAnimation { model.history.forEach { model.favorites.add($0) } }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.16)))
                .help("Ajouter toutes les radios récentes aux favoris")
            }
        } else if !compact {
            HStack(spacing: 10) {
                Text("Aucune radio favorite").font(.callout).foregroundStyle(.white.opacity(0.7))
                Button("Rechercher une station", action: onSearch)
                Button("Importer…") { model.importFavorites() }
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
        }
    }

    /// Défilement horizontal, bords estompés.
    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: compact ? 6 : 8) { content() }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
        }
        .scrollIndicators(.never)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.97), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}

// MARK: - Fenêtre principale

struct ImmersiveMainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AmbientSeed.storageKey) private var lastCover = ""
    @State private var showSearch = false

    var body: some View {
        let store = model.store
        let cover = NowPlayingText.cover(model)
        GeometryReader { geo in
        ZStack {
            VStack(spacing: 0) {
                topBar(wide: geo.size.width >= 700)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                center
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 32)
                if store.status != .notConfigured {
                    favoritesBar
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }
            if showSearch { searchOverlay }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        }
        .background {
            ImmersiveBackdrop(cover: cover, ambientSeed: AmbientSeed.resolve(model, stored: lastCover))
                .ignoresSafeArea()
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.3), value: store.snapshot.player.title)
        .animation(.easeInOut(duration: 0.45), value: store.snapshot.isOn)
        .animation(.spring(duration: 0.3), value: showSearch)
        .onChange(of: cover, initial: true) { _, new in
            AmbientSeed.remember(new, model: model, stored: &lastCover)
        }
    }

    // MARK: Barre supérieure

    /// `wide` = assez de place pour les icônes de source ; sinon elles passent dans un menu.
    private func topBar(wide: Bool) -> some View {
        let store = model.store
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.speakerTitle).font(.headline).lineLimit(1)
                    if model.isDemo {
                        Text("DÉMO").font(.system(size: 9, weight: .bold)).tracking(1).fixedSize()
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(.white.opacity(0.2)))
                    }
                }
                HStack(spacing: 5) {
                    StatusDot(status: store.status)
                    Text(store.status.isOnline ? (store.snapshot.modelLabel ?? String(localized: "Connectée")) : store.status.label)
                        .font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
            }
            .padding(.leading, 6)
            Spacer(minLength: 8)
            if store.status != .notConfigured {
                if wide {
                    ImmersiveSourceIcons(store: store)
                } else {
                    sourceMenu
                }
                Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 18)
                Button { showSearch = false; model.toggleExplorer() } label: { Image(systemName: "safari") }
                    .buttonStyle(GlassIconStyle(active: model.showsExplorer))
                    .help("Explorer les radios par pays, genre et langue (⌘E)")
                    .accessibilityLabel("Explorer les radios")
                Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(GlassIconStyle(active: showSearch))
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Rechercher une station (⌘F)")
                    .accessibilityLabel("Rechercher une station")
            }
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(GlassIconStyle())
                .help("Réglages (⌘,)")
                .accessibilityLabel("Réglages")
            ImmersivePowerButton(store: store)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(.black.opacity(0.15))
            Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    /// Sources dans un menu (fenêtre étroite) : icône de la source en cours.
    private var sourceMenu: some View {
        let store = model.store
        let snap = store.snapshot
        return Menu {
            ForEach(snap.sources) { source in
                Button { Task { await store.selectSource(source) } } label: {
                    Label(source.label, systemImage: snap.isOn && snap.source == source ? "checkmark" : source.symbol)
                }
            }
        } label: {
            Image(systemName: (snap.isOn ? snap.source : nil)?.symbol ?? "hifispeaker")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .disabled(!store.status.isOnline)
        .help("Source : \(snap.source?.label ?? "—")")
        .accessibilityLabel("Source")
    }

    // MARK: Centre

    @ViewBuilder
    private var center: some View {
        let store = model.store
        switch store.status {
        case .notConfigured:
            VStack(spacing: 18) {
                Text("Bienvenue").font(.system(size: 40, weight: .heavy))
                SetupCard()
                    .padding(20)
                    .frame(maxWidth: 460)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            }
        case .offline, .connecting:
            statusScreen(symbol: store.status == .connecting ? "antenna.radiowaves.left.and.right" : "wifi.exclamationmark",
                         title: NowPlayingText.title(model), subtitle: store.status.label,
                         action: store.status == .connecting ? nil : (String(localized: "Réessayer"), { store.retryNow() }))
        case .online:
            if store.snapshot.isOn {
                nowPlaying.transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                standby.transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
    }

    private var nowPlaying: some View {
        let store = model.store
        let snap = store.snapshot
        return GeometryReader { geo in
            let roomy = geo.size.height > 470
            let side = max(140, min(geo.size.width * 0.5, geo.size.height - (roomy ? 290 : 250), 430))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                CoverArtwork(snapshot: snap, cornerRadius: side * 0.06)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.45), radius: side * 0.09, y: side * 0.05)
                    .padding(.bottom, roomy ? 26 : 16)
                Text(NowPlayingText.title(model))
                    .font(.system(size: roomy ? 40 : 30, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.opacity)
                Text(NowPlayingText.subtitle(model))
                    .font(roomy ? .title2 : .title3)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .padding(.top, 2)
                ImmersiveProgress(store: store)
                    .frame(width: min(geo.size.width, max(side, 320)))
                    .frame(minHeight: 14)
                    .padding(.top, roomy ? 16 : 10)
                ImmersiveTransport(size: roomy ? 68 : 58)
                    .padding(.top, roomy ? 10 : 6)
                ImmersiveVolume(store: store)
                    .frame(width: 280)
                    .padding(.top, roomy ? 14 : 8)
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var standby: some View {
        let store = model.store
        return VStack(spacing: 0) {
            StandbyPowerButton(size: 132) { Task { await store.togglePower() } }
                .padding(.bottom, 28)
            Text("En veille").font(.system(size: 40, weight: .heavy))
            Text(model.favorites.items.isEmpty && model.history.isEmpty ? "Touchez ⏻ pour allumer" : "Touchez ⏻ ou une radio ci-dessous pour allumer")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
    }

    private func statusScreen(symbol: String, title: String, subtitle: String,
                              action: (String, () -> Void)?) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 132, height: 132)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .padding(.bottom, 28)
            Text(title).font(.system(size: 36, weight: .heavy))
            Text(subtitle).font(.title3).foregroundStyle(.white.opacity(0.72)).lineLimit(2).padding(.top, 4)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.18)))
                    .padding(.top, 18)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: Favoris (bas de fenêtre)

    private var favoritesBar: some View {
        HStack(spacing: 6) {
            CurrentFavoriteButton(size: 15)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.1)))
            ImmersiveFavoritesStrip(onSearch: { showSearch = true })
                .frame(maxWidth: .infinity)
            FavoritesMenu(size: 15)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .frame(minHeight: 50)
    }

    // MARK: Recherche (panneau)

    private var searchOverlay: some View {
        @Bindable var model = model
        return ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showSearch = false }
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Radios").font(.title3.weight(.bold))
                    Spacer()
                    CurrentFavoriteButton(size: 14)
                    FavoritesMenu(size: 14)
                    Button { showSearch = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(GlassIconStyle(size: 24))
                        .help("Fermer (Échap)")
                        .accessibilityLabel("Fermer la recherche")
                }
                SearchField(text: $model.searchText, isSearching: model.isSearching, prompt: "Rechercher une station",
                            autoFocus: true)
                ScrollView {
                    RadioContent {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favoris").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                                .padding(.leading, 8)
                            ForEach(model.favorites.items) { StationRow(station: $0) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
            .padding(16)
            .frame(width: 400)
            .frame(maxHeight: 520)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.3))
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            .padding(.top, 58)
            .padding(.trailing, 14)
            .padding(.bottom, 20)
            .onExitCommand { showSearch = false }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Grand bouton marche de la veille : disque translucide, anneau qui « respire ».
private struct StandbyPowerButton: View {
    var size: CGFloat
    var action: () -> Void
    @State private var breathe = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.white.opacity(0.06))
                    .frame(width: size * 1.45, height: size * 1.45)
                    .scaleEffect(breathe ? 1.06 : 0.94)
                    .opacity(breathe ? 0.5 : 1)
                Circle().fill(RadialGradient(colors: [.white.opacity(hovering ? 0.26 : 0.18), .white.opacity(0.04)],
                                             center: UnitPoint(x: 0.35, y: 0.25), startRadius: 0, endRadius: size * 0.8))
                Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
                Image(systemName: "power")
                    .font(.system(size: size * 0.36, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathe = true }
        }
        .help("Allumer (⇧⌘P)")
        .accessibilityLabel("Allumer l'enceinte")
    }
}

// MARK: - Mini-lecteur

struct ImmersiveMiniPlayer: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AmbientSeed.storageKey) private var lastCover = ""

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                StatusDot(status: store.status)
                Text(model.speakerTitle).font(.headline).lineLimit(1)
                Spacer()
                OpenMainWindowButton { Image(systemName: "macwindow") }
                    .buttonStyle(GlassIconStyle(size: 26))
                ImmersivePowerButton(store: store, size: 26)
            }

            if store.status.isOnline && snap.isOn {
                CoverArtwork(snapshot: snap, cornerRadius: 12)
                    .frame(width: 168, height: 168)
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    .padding(.top, 4)
                VStack(spacing: 2) {
                    Text(NowPlayingText.compactTitle(model)).font(.title3.weight(.heavy)).lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(NowPlayingText.compactSubtitle(model)).font(.callout).foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                ImmersiveProgress(store: store, showTimes: false)
                    .frame(width: 220)
                ImmersiveTransport(size: 48)
                ImmersiveVolume(store: store, knob: 10)
                    .padding(.horizontal, 8)
            } else {
                Group {
                    if store.status.isOnline {
                        StandbyPowerButton(size: 84) { Task { await store.togglePower() } }
                    } else {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 30, weight: .light))
                            .frame(width: 84, height: 84)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .padding(.vertical, 18)
                VStack(spacing: 2) {
                    Text(NowPlayingText.compactTitle(model)).font(.title3.weight(.heavy))
                    Text(store.status.isOnline ? String(localized: "Touchez ⏻ ou une radio") : store.status.label)
                        .font(.callout).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                }
                .multilineTextAlignment(.center)
            }

            ImmersiveSourceIcons(store: store, size: 26)

            if !model.favorites.items.isEmpty || (model.favorites.suggestHistory && !model.history.isEmpty) {
                ImmersiveFavoritesStrip(compact: true)
                    .padding(.horizontal, -16)
            }

            MiniPlayerFooter()
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .frame(width: 320)
        .background(ImmersiveBackdrop(cover: NowPlayingText.cover(model),
                                      ambientSeed: AmbientSeed.resolve(model, stored: lastCover)))
        .foregroundStyle(.white)
        .onChange(of: NowPlayingText.cover(model), initial: true) { _, new in
            AmbientSeed.remember(new, model: model, stored: &lastCover)
        }
    }
}
