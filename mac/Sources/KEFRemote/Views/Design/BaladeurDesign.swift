import AppKit
import KEFKit
import SwiftUI

// Design « Baladeur » : boîtier de baladeur MP3 des années 2000, écran LCD rétro à menus
// et molette cliquable (tourner = volume ou défilement, MENU = retour, bas = lecture/pause,
// gauche/droite = piste précédente/suivante, bouton central = sélectionner).

// MARK: - Couleurs

enum BaladeurPalette {
    // Écran LCD (identique en clair et en sombre : c'est un objet).
    static let lcdTop = Color(hex: 0xDDE6ED)
    static let lcdBottom = Color(hex: 0xBAC6D0)
    static let ink = Color(hex: 0x18212A)
    static let inkDim = Color(hex: 0x53606B)
    static let titleTop = Color(hex: 0xF5F7F9)
    static let titleBottom = Color(hex: 0xC7D0D8)
    static let titleRule = Color(hex: 0x8794A0)
    static let selectTop = Color(hex: 0x6DB4F6)
    static let selectBottom = Color(hex: 0x2770D8)
    static let offTop = Color(hex: 0x3A4148)
    static let offBottom = Color(hex: 0x1F2428)
    static let accent = Color(hex: 0x2F74DA)

    /// Façade : blanc nacré (clair) ou aluminium (sombre).
    static func body(_ dark: Bool) -> LinearGradient {
        dark
            ? LinearGradient(colors: [Color(hex: 0xA9ACB1), Color(hex: 0x82858A), Color(hex: 0x6A6D72)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xFDFDFC), Color(hex: 0xEFEFEC), Color(hex: 0xE2E2DE)],
                             startPoint: .top, endPoint: .bottom)
    }

    static func wheel(_ dark: Bool) -> LinearGradient {
        dark
            ? LinearGradient(colors: [Color(hex: 0x323336), Color(hex: 0x1C1D1F)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xEEEEEB)], startPoint: .top, endPoint: .bottom)
    }

    static func wheelLabel(_ dark: Bool) -> Color { dark ? Color(hex: 0xD6D7D9) : Color(hex: 0xA3A6AA) }

    static func window(_ dark: Bool) -> RadialGradient {
        RadialGradient(colors: dark ? [Color(hex: 0x303134), Color(hex: 0x111214)] : [Color(hex: 0xF4F2EF), Color(hex: 0xCFCAC4)],
                       center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 900)
    }
}

// MARK: - Navigation

/// Écrans du baladeur. Les quatre derniers dépendent de l'état de l'enceinte et ne sont
/// jamais empilés.
enum BaladeurScreen: String, Hashable {
    case menu, nowPlaying, options, favorites, reorder, search, sources, recent
    case setup, offline, standby

    var title: String {
        switch self {
        case .menu: "Menu"
        case .nowPlaying: "À l'écoute"
        case .options: "Options"
        case .favorites: "Radios"
        case .reorder: "Ordre des radios"
        case .search: "Recherche"
        case .sources: "Sources"
        case .recent: "Récentes"
        case .setup: "Enceintes"
        case .offline: "Hors ligne"
        case .standby: "Veille"
        }
    }

    /// Notification de développement (captures) : `object` = `rawValue` de l'écran.
    static let showNotification = Notification.Name("KEFBaladeurShowScreen")
}

/// Pile d'écrans, sélection par écran, affichage temporaire du volume, déplacement d'un
/// favori en cours (mode « Ordre des radios »).
@MainActor @Observable
final class BaladeurNavigator {
    private(set) var stack: [BaladeurScreen] = [.menu, .nowPlaying]
    private var selections: [BaladeurScreen: Int] = [:]
    private(set) var showsVolume = false
    var grabbed: String?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?

    var current: BaladeurScreen { stack.last ?? .menu }

    func push(_ screen: BaladeurScreen) {
        if screen == .nowPlaying, let i = stack.firstIndex(of: .nowPlaying) { stack.removeSubrange(i...) }
        stack.append(screen)
    }

    func pop() {
        grabbed = nil
        if stack.count > 1 { stack.removeLast() }
    }

    func reset(to screen: BaladeurScreen) {
        grabbed = nil
        stack = screen == .menu ? [.menu] : [.menu, screen]
    }

    func selection(_ screen: BaladeurScreen) -> Int { selections[screen] ?? 0 }

    func select(_ index: Int, in screen: BaladeurScreen, count: Int) {
        selections[screen] = count > 0 ? min(max(0, index), count - 1) : 0
    }

    func flashVolume() {
        showsVolume = true
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.showsVolume = false }
        }
    }
}

/// Ligne de menu.
struct BaladeurRow: Identifiable {
    enum Trailing { case chevron, check, playing, favorite(Bool), grab, none }

    let id: String
    var title: String
    var detail: String?
    var station: Station?
    var trailing: Trailing = .none
    var enabled = true
    /// Indice dans les favoris : glisser-déposer et menu contextuel communs.
    var favoriteIndex: Int?
    var action: () -> Void
}

// MARK: - Boîtier

/// Le baladeur complet (écran + molette), à la taille demandée.
struct BaladeurDevice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme
    let width: CGFloat
    var compact = false
    @State private var nav = BaladeurNavigator()
    @State private var scroll = ScrollAccumulator()
    @FocusState private var focused: Bool

    var body: some View {
        let dark = scheme == .dark
        let pad = width * 0.075
        let screenWidth = width - pad * 2
        let screenHeight = screenWidth * (compact ? 0.72 : 0.76)
        let wheel = width * (compact ? 0.62 : 0.64)
        let height = screenHeight + wheel + pad * (compact ? 3.4 : 4.2)
        let screen = effectiveScreen
        let rows = rows(for: screen)
        VStack(spacing: 0) {
            BaladeurScreenView(nav: nav, screen: screen, rows: rows, compact: compact,
                               onActivate: { activate(rows, at: $0, in: screen) },
                               onSearchExit: { nav.pop(); focused = true })
                .frame(width: screenWidth, height: screenHeight)
                .padding(.top, pad)
            Spacer(minLength: 0)
            ClickWheel(diameter: wheel, dark: dark,
                       onRotate: { rotate($0, rows: rows, screen: screen) },
                       onMenu: { menu(screen) },
                       onPlayPause: { Task { await model.store.playPause() } },
                       onPrevious: { model.skip(.previous) },
                       onNext: { model.skip(.next) },
                       previousLabel: model.skipPlan(.previous).label,
                       nextLabel: model.skipPlan(.next).label,
                       onSelect: { activate(rows, at: nav.selection(screen), in: screen) })
            Spacer(minLength: 0)
        }
        .frame(width: width, height: height)
        .background {
            let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
            shape.fill(BaladeurPalette.body(dark))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.5 : 0.95), .black.opacity(0.12)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                .overlay(shape.strokeBorder(.black.opacity(dark ? 0.35 : 0.1), lineWidth: 0.5).padding(-0.5))
                .shadow(color: .black.opacity(dark ? 0.55 : 0.22), radius: compact ? 10 : 34, y: compact ? 4 : 20)
        }
        .background(ScrollWheelReader { delta, precise in
            let steps = scroll.steps(for: delta, precise: precise)
            if steps != 0 { scrollUp(steps, rows: rows, screen: screen) }
        })
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .escape]) { press in
            switch press.key {
            case .upArrow: scrollUp(1, rows: rows, screen: screen)
            case .downArrow: scrollUp(-1, rows: rows, screen: screen)
            case .leftArrow, .escape: menu(screen)
            default: activate(rows, at: nav.selection(screen), in: screen)
            }
            return .handled
        }
        .onAppear { if !compact { focused = true } }
        .onReceive(NotificationCenter.default.publisher(for: BaladeurScreen.showNotification)) { note in
            guard !compact, let raw = note.object as? String, let target = BaladeurScreen(rawValue: raw) else { return }
            nav.reset(to: target)
            if target == .menu { nav.select(1, in: .menu, count: 9) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Baladeur")
    }

    // MARK: État

    private var effectiveScreen: BaladeurScreen {
        let store = model.store
        switch store.status {
        case .notConfigured: return .setup
        case .offline, .connecting: return .offline
        case .online: return store.snapshot.isOn ? nav.current : .standby
        }
    }

    // MARK: Commandes de la molette

    /// Rotation horaire positive : descendre dans la liste ou monter le volume.
    private func rotate(_ steps: Int, rows: [BaladeurRow], screen: BaladeurScreen) {
        if screen == .nowPlaying {
            model.store.adjustVolume(by: steps * 2)
            nav.flashVolume()
        } else {
            move(steps, rows: rows, screen: screen)
        }
    }

    /// Molette de la souris / flèches : vers le haut = remonter la liste ou monter le volume.
    private func scrollUp(_ steps: Int, rows: [BaladeurRow], screen: BaladeurScreen) {
        if screen == .nowPlaying {
            model.store.adjustVolume(by: steps * 2)
            nav.flashVolume()
        } else {
            move(-steps, rows: rows, screen: screen)
        }
    }

    private func move(_ steps: Int, rows: [BaladeurRow], screen: BaladeurScreen) {
        guard !rows.isEmpty else { return }
        let old = nav.selection(screen)
        let new = min(max(0, old + steps), rows.count - 1)
        guard new != old else { return }
        if screen == .reorder, let id = nav.grabbed {
            // Déplacement du favori « saisi » d'un cran à la fois.
            let items = model.favorites.items
            guard items.indices.contains(old), items.indices.contains(new), items[old].id == id else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                if new > old { model.favorites.move(id: items[new].id, before: id) }
                else { model.favorites.move(id: id, before: items[new].id) }
            }
        }
        nav.select(new, in: screen, count: rows.count)
    }

    private func menu(_ screen: BaladeurScreen) {
        switch screen {
        case .setup, .offline, .standby: return
        default: withAnimation(.easeOut(duration: 0.18)) { nav.pop() }
        }
        if !compact { focused = true }
    }

    private func activate(_ rows: [BaladeurRow], at index: Int, in screen: BaladeurScreen) {
        switch screen {
        case .standby:
            Task { await model.store.togglePower() }
        case .nowPlaying:
            withAnimation(.easeOut(duration: 0.18)) { nav.push(.options) }
        default:
            guard rows.indices.contains(index), rows[index].enabled else { return }
            nav.select(index, in: screen, count: rows.count)
            rows[index].action()
        }
    }

    private func go(_ screen: BaladeurScreen) {
        withAnimation(.easeOut(duration: 0.18)) { nav.push(screen) }
    }

    private func playAndShow(_ station: Station) {
        model.play(station)
        go(.nowPlaying)
    }

    // MARK: Contenu des menus

    private func rows(for screen: BaladeurScreen) -> [BaladeurRow] {
        let store = model.store
        let snap = store.snapshot
        switch screen {
        case .menu:
            var rows = [
                BaladeurRow(id: "now", title: "À l'écoute", trailing: .chevron) { go(.nowPlaying) },
                BaladeurRow(id: "fav", title: "Radios favorites", trailing: .chevron) { go(.favorites) },
            ]
            if !compact {
                rows.append(BaladeurRow(id: "search", title: "Recherche", trailing: .chevron) { go(.search) })
            }
            rows += [
                BaladeurRow(id: "src", title: "Sources", trailing: .chevron) { go(.sources) },
                BaladeurRow(id: "recent", title: "Écoutées récemment", trailing: .chevron) { go(.recent) },
            ]
            if compact {
                rows.append(BaladeurRow(id: "open", title: "Ouvrir KEF Remote", trailing: .chevron) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                })
            }
            rows += [
                BaladeurRow(id: "settings", title: "Réglages", trailing: .chevron) {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                },
                BaladeurRow(id: "sleep", title: "Mettre en veille") { Task { await store.togglePower() } },
            ]
            return rows

        case .options:
            let current = snap.currentStation
            let isFavorite = model.favorites.contains(current)
            return [
                BaladeurRow(id: "star", title: isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                            detail: current?.title, trailing: .favorite(isFavorite), enabled: current != nil) {
                    model.toggleCurrentFavorite()
                    nav.pop()
                },
                BaladeurRow(id: "mute", title: snap.isMuted ? "Rétablir le son" : "Couper le son") {
                    store.toggleMute()
                    nav.pop()
                },
                BaladeurRow(id: "src", title: "Source", detail: snap.source?.label, trailing: .chevron) { go(.sources) },
                BaladeurRow(id: "sleep", title: "Mettre en veille") { Task { await store.togglePower() } },
            ]

        case .favorites:
            var rows = model.favorites.items.enumerated().map { index, station in
                BaladeurRow(id: station.id, title: station.title, station: station,
                            trailing: model.isCurrent(station) ? .playing : .chevron, favoriteIndex: index) {
                    playAndShow(station)
                }
            }
            if rows.isEmpty {
                rows.append(BaladeurRow(id: "empty", title: "Aucune radio favorite", enabled: false) {})
                if !model.history.isEmpty {
                    rows.append(BaladeurRow(id: "recent", title: "Écoutées récemment", trailing: .chevron) { go(.recent) })
                }
                if !compact {
                    rows.append(BaladeurRow(id: "search", title: "Rechercher une station", trailing: .chevron) { go(.search) })
                }
                rows.append(BaladeurRow(id: "import", title: "Importer…") { model.importFavorites() })
            } else if rows.count > 1 {
                rows.append(BaladeurRow(id: "reorder", title: "Modifier l'ordre…", trailing: .chevron) { go(.reorder) })
            }
            return rows

        case .reorder:
            return model.favorites.items.map { station in
                BaladeurRow(id: station.id, title: station.title, station: station,
                            trailing: nav.grabbed == station.id ? .grab : .none) {
                    nav.grabbed = nav.grabbed == station.id ? nil : station.id
                }
            }

        case .search:
            return model.searchResults.map { station in
                BaladeurRow(id: station.id, title: station.title, detail: station.description, station: station,
                            trailing: .favorite(model.favorites.contains(station))) {
                    playAndShow(station)
                }
            }

        case .sources:
            return snap.sources.map { source in
                BaladeurRow(id: source.rawValue, title: source.label, trailing: snap.source == source ? .check : .none) {
                    Task { await store.selectSource(source) }
                }
            }

        case .recent:
            var rows: [BaladeurRow] = []
            let missing = model.history.filter { !model.favorites.contains($0) }
            if !missing.isEmpty {
                rows.append(BaladeurRow(id: "addall", title: "Tout ajouter aux favoris", detail: "\(missing.count)") {
                    withAnimation { model.history.forEach { model.favorites.add($0) } }
                    model.showToast("Radios récentes ajoutées aux favoris")
                })
            }
            rows += model.history.map { station in
                BaladeurRow(id: station.id, title: station.title, station: station,
                            trailing: model.isCurrent(station) ? .playing : .favorite(model.favorites.contains(station))) {
                    playAndShow(station)
                }
            }
            if model.history.isEmpty {
                rows.append(BaladeurRow(id: "none", title: model.historyLoaded ? "Aucune radio récente" : "Chargement…",
                                        enabled: false) {})
            }
            return rows

        case .setup:
            var rows = model.discovery.kefSpeakers.map { speaker in
                BaladeurRow(id: speaker.id, title: speaker.name, detail: speaker.host, trailing: .chevron,
                            enabled: speaker.host != nil) {
                    if let host = speaker.host { try? model.setHost(host) }
                }
            }
            rows.append(BaladeurRow(id: "settings", title: "Réglages…", trailing: .chevron) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            })
            return rows

        case .offline:
            return [BaladeurRow(id: "retry", title: "Réessayer", enabled: store.status != .connecting) { store.retryNow() }]

        case .nowPlaying, .standby:
            return []
        }
    }
}

// MARK: - Écran

private struct BaladeurScreenView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let nav: BaladeurNavigator
    let screen: BaladeurScreen
    let rows: [BaladeurRow]
    let compact: Bool
    let onActivate: (Int) -> Void
    let onSearchExit: () -> Void

    var body: some View {
        let radius: CGFloat = compact ? 6 : 9
        ZStack {
            if screen == .standby {
                standby
            } else {
                VStack(spacing: 0) {
                    titleBar
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .background(LinearGradient(colors: [BaladeurPalette.lcdTop, BaladeurPalette.lcdBottom],
                                           startPoint: .top, endPoint: .bottom))
            }
        }
        .foregroundStyle(BaladeurPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: radius - 3, style: .continuous))
        .overlay {
            // Reflet du verre.
            LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .clear, location: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: radius - 3, style: .continuous))
                .allowsHitTesting(false)
        }
        .padding(compact ? 3 : 4)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(hex: 0x111315)))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.18), value: screen)
    }

    private var titleFont: Font { .system(size: compact ? 10 : 12, weight: .bold) }
    private var rowFont: Font { .system(size: compact ? 11 : 13.5, weight: .semibold) }
    private var rowHeight: CGFloat { compact ? 17 : 22 }

    // MARK: Barre de titre

    private var titleBar: some View {
        let store = model.store
        let snap = store.snapshot
        // Colonnes latérales de même largeur : le titre reste centré (et tronqué au besoin).
        let side: CGFloat = compact ? 40 : 66
        return HStack(spacing: 4) {
            Image(systemName: snap.isPlaying ? "play.fill" : (snap.isOn && store.status.isOnline ? "pause.fill" : "stop.fill"))
                .font(.system(size: compact ? 7 : 8, weight: .bold))
                .foregroundStyle(BaladeurPalette.accent)
                .frame(width: side, alignment: .leading)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(screen == .menu || screen == .nowPlaying ? model.speakerTitle : screen.title)
                .font(titleFont)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            HStack(spacing: compact ? 4 : 5) {
                if model.isDemo && !compact { Text("DÉMO").font(.system(size: 8, weight: .heavy)).fixedSize() }
                Image(systemName: store.status.isOnline ? "wifi" : "wifi.slash")
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .accessibilityLabel(store.status.isOnline ? "Connectée" : "Hors ligne")
                // Raccourci vers les Réglages (comme ⌘,).
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: compact ? 8 : 9.5, weight: .bold))
                        .frame(width: compact ? 11 : 13, height: compact ? 11 : 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Réglages (⌘,)")
                .accessibilityLabel("Réglages")
            }
            .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: compact ? 15 : 19)
        .background(LinearGradient(colors: [BaladeurPalette.titleTop, BaladeurPalette.titleBottom],
                                   startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Rectangle().fill(BaladeurPalette.titleRule).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .nowPlaying:
            BaladeurNowPlaying(nav: nav, compact: compact)
        case .search:
            VStack(spacing: 0) {
                searchField
                if model.searchResults.isEmpty {
                    message(model.searchError ?? (model.searchText.isEmpty ? "Tapez le nom d'une station" : " "))
                } else {
                    list
                }
            }
        case .offline:
            VStack(spacing: 0) {
                message(model.store.status == .connecting ? "Connexion…" : "Enceinte indisponible", bold: true)
                Text(model.store.status.label).font(.system(size: compact ? 9 : 11)).foregroundStyle(BaladeurPalette.inkDim)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 8).padding(.bottom, 6)
                list
            }
        case .setup:
            VStack(spacing: 0) {
                message(model.discovery.kefSpeakers.isEmpty ? "Recherche des enceintes…" : "Choisissez une enceinte")
                list
            }
        default:
            list
        }
    }

    private func message(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: compact ? 10 : 12, weight: bold ? .bold : .regular))
            .foregroundStyle(bold ? BaladeurPalette.ink : BaladeurPalette.inkDim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 6 : 10)
    }

    private var list: some View {
        GeometryReader { geo in
            let visible = max(1, Int(geo.size.height / rowHeight))
            let sel = nav.selection(screen)
            let window = ClickWheelGeometry.window(selection: sel, count: rows.count, visible: visible)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(window, id: \.self) { index in
                        rowView(rows[index], index: index, selected: index == sel)
                    }
                    Spacer(minLength: 0)
                }
                if rows.count > visible {
                    scrollBar(window: window, total: rows.count)
                }
            }
        }
    }

    private func scrollBar(window: Range<Int>, total: Int) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let thumb = max(10, h * CGFloat(window.count) / CGFloat(total))
            let y = (h - thumb) * CGFloat(window.lowerBound) / CGFloat(max(1, total - window.count))
            ZStack(alignment: .top) {
                Rectangle().fill(.white.opacity(0.5))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LinearGradient(colors: [BaladeurPalette.selectTop, BaladeurPalette.selectBottom],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: thumb)
                    .offset(y: y)
            }
            .overlay(Rectangle().strokeBorder(BaladeurPalette.titleRule, lineWidth: 0.5))
        }
        .frame(width: compact ? 5 : 7)
    }

    @ViewBuilder
    private func rowView(_ row: BaladeurRow, index: Int, selected: Bool) -> some View {
        let grabbed = row.trailing.isGrab
        let base = HStack(spacing: 6) {
            if let station = row.station, !compact {
                StationLogo(station: station, cornerRadius: 3)
                    .frame(width: rowHeight - 6, height: rowHeight - 6)
            }
            Text(row.title)
                .font(rowFont)
                .lineLimit(1)
            if let detail = row.detail, !compact {
                Text(detail).font(.system(size: 11)).lineLimit(1)
                    .foregroundStyle(selected ? .white.opacity(0.8) : BaladeurPalette.inkDim)
            }
            Spacer(minLength: 4)
            trailing(row, selected: selected)
        }
        .padding(.horizontal, 6)
        .frame(height: rowHeight)
        .foregroundStyle(selected ? Color.white : (row.enabled ? BaladeurPalette.ink : BaladeurPalette.inkDim))
        .background {
            if selected {
                LinearGradient(colors: grabbed ? [Color(hex: 0xF6B46D), Color(hex: 0xD8742A)]
                                               : [BaladeurPalette.selectTop, BaladeurPalette.selectBottom],
                               startPoint: .top, endPoint: .bottom)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.35)).frame(height: 1) }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title + (row.detail.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)

        if let favIndex = row.favoriteIndex, let station = row.station {
            // Favoris : lecture d'un clic, glisser-déposer, menu contextuel (comportement commun).
            base
                .favoriteInteractions(station: station, index: favIndex, dropTarget: .constant(nil))
                .simultaneousGesture(TapGesture().onEnded {
                    nav.select(index, in: screen, count: rows.count)
                    withAnimation(.easeOut(duration: 0.18)) { nav.push(.nowPlaying) }
                })
        } else {
            base
                .onTapGesture { onActivate(index) }
                .contextMenu {
                    if let station = row.station {
                        Button("Lire") { model.play(station) }
                        Button(model.favorites.contains(station) ? "Retirer des favoris" : "Ajouter aux favoris") {
                            withAnimation { model.favorites.toggle(station) }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func trailing(_ row: BaladeurRow, selected: Bool) -> some View {
        let size: CGFloat = compact ? 9 : 11
        switch row.trailing {
        case .chevron:
            Text("›").font(.system(size: size + 5, weight: .bold))
        case .check:
            Image(systemName: "checkmark").font(.system(size: size, weight: .bold))
        case .playing:
            Image(systemName: "speaker.wave.2.fill").font(.system(size: size))
        case .favorite(let on):
            if let station = row.station {
                Button { withAnimation { model.favorites.toggle(station) } } label: {
                    Image(systemName: on ? "star.fill" : "star").font(.system(size: size, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(on ? "Retirer des favoris" : "Ajouter aux favoris")
                .accessibilityLabel(on ? "Retirer \(station.title) des favoris" : "Ajouter \(station.title) aux favoris")
            } else {
                Image(systemName: on ? "star.fill" : "star").font(.system(size: size, weight: .semibold))
            }
        case .grab:
            Image(systemName: "arrow.up.arrow.down").font(.system(size: size, weight: .bold))
        case .none:
            EmptyView()
        }
    }

    // MARK: Recherche

    private var searchField: some View {
        @Bindable var model = model
        return BaladeurSearchField(text: $model.searchText, isSearching: model.isSearching, compact: compact,
                                   onSubmit: { if !rows.isEmpty { onActivate(nav.selection(.search)) } },
                                   onExit: onSearchExit)
    }

    // MARK: Veille

    private var standby: some View {
        ZStack {
            LinearGradient(colors: [BaladeurPalette.offTop, BaladeurPalette.offBottom], startPoint: .top, endPoint: .bottom)
            VStack(spacing: compact ? 4 : 8) {
                Image(systemName: "power").font(.system(size: compact ? 20 : 30, weight: .light))
                Text("En veille").font(.system(size: compact ? 13 : 17, weight: .bold))
                Text("Bouton central : allumer").font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(Color(hex: 0x7D8892))
            }
            .foregroundStyle(Color(hex: 0xA3AEB8))
        }
        .accessibilityElement(children: .combine)
    }
}

private extension BaladeurRow.Trailing {
    var isGrab: Bool { if case .grab = self { true } else { false } }
}

/// Champ de saisie « LCD » (prend le focus à l'ouverture de l'écran Recherche).
private struct BaladeurSearchField: View {
    @Binding var text: String
    var isSearching: Bool
    var compact: Bool
    var onSubmit: () -> Void
    var onExit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .bold))
            TextField("Nom de la station", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand { if text.isEmpty { onExit() } else { text = "" } }
            if isSearching { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(BaladeurPalette.titleRule, lineWidth: 1))
        .padding(5)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
    }
}

// MARK: - À l'écoute

private struct BaladeurNowPlaying: View {
    @Environment(AppModel.self) private var model
    let nav: BaladeurNavigator
    let compact: Bool

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let isFavorite = model.favorites.contains(snap.currentStation)
        GeometryReader { geo in
            let side = min(geo.size.height * 0.62, geo.size.width * 0.42)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: compact ? 7 : 10) {
                    CoverArtwork(snapshot: snap, cornerRadius: 2)
                        .frame(width: side, height: side)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                        Text(NowPlayingText.compactTitle(model))
                            .font(.system(size: compact ? 12 : 15, weight: .bold))
                            .lineLimit(2)
                        Text(NowPlayingText.compactSubtitle(model))
                            .font(.system(size: compact ? 10 : 12.5, weight: .semibold))
                            .foregroundStyle(BaladeurPalette.inkDim)
                            .lineLimit(2)
                        Text((snap.source ?? .wifi).label)
                            .font(.system(size: compact ? 9 : 11))
                            .foregroundStyle(BaladeurPalette.inkDim)
                        Spacer(minLength: 0)
                        if !compact {
                            HStack(spacing: 4) {
                                Button { model.toggleCurrentFavorite() } label: {
                                    Image(systemName: isFavorite ? "star.fill" : "star")
                                }
                                .buttonStyle(.plain)
                                .disabled(snap.currentStation == nil)
                                .help(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris (⌘D)")
                                .accessibilityLabel(isFavorite ? "Retirer la radio des favoris" : "Ajouter la radio aux favoris")
                                Text("Centre : options").foregroundStyle(BaladeurPalette.inkDim)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: side)
                }
                Spacer(minLength: 0)
                Group {
                    if nav.showsVolume {
                        volumeBar(snap)
                    } else {
                        progress(snap)
                    }
                }
                .frame(height: compact ? 18 : 24)
                .transition(.opacity)
            }
            .padding(compact ? 7 : 10)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.2), value: nav.showsVolume)
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.white.opacity(0.9), Color(hex: 0xC9D2DA)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [BaladeurPalette.selectTop, BaladeurPalette.selectBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(BaladeurPalette.titleRule, lineWidth: 0.75))
        }
        .frame(height: compact ? 6 : 8)
    }

    private func volumeBar(_ snap: SpeakerSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: snap.isMuted ? "speaker.slash.fill" : "speaker.fill").font(.system(size: 10))
            bar(Double(snap.volume) / 100)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(snap.volume) %")
    }

    @ViewBuilder
    private func progress(_ snap: SpeakerSnapshot) -> some View {
        let store = model.store
        if let duration = snap.player.durationMs, !snap.player.isLive {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let position = store.estimatedPosition(at: context.date) ?? 0
                VStack(spacing: 2) {
                    bar(duration > 0 ? Double(position) / Double(duration) : 0)
                    HStack {
                        Text(formatTime(position))
                        Spacer()
                        Text("-" + formatTime(max(0, duration - position)))
                    }
                    .font(.system(size: compact ? 8 : 9.5, weight: .semibold).monospacedDigit())
                }
            }
        } else {
            HStack(spacing: 6) {
                EqualizerBars(animating: snap.isPlaying, color: BaladeurPalette.accent)
                Text(snap.player.isLive ? "EN DIRECT" : (snap.isPlaying ? "EN LECTURE" : "EN PAUSE"))
                    .font(.system(size: compact ? 9 : 11, weight: .heavy))
                    .tracking(1)
                Spacer()
                Text("VOL \(snap.volume)")
                    .font(.system(size: compact ? 9 : 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(BaladeurPalette.inkDim)
            }
        }
    }
}

// MARK: - Molette cliquable

/// Anneau tactile : glisser en rond = crans (avec retour haptique), clic sur une des
/// quatre zones, bouton central séparé. VoiceOver : réglable + actions nommées.
private struct ClickWheel: View {
    let diameter: CGFloat
    let dark: Bool
    var onRotate: (Int) -> Void
    var onMenu: () -> Void
    var onPlayPause: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    /// Libellés VoiceOver des zones gauche / droite (« Radio précédente » sur une radio).
    var previousLabel = "Piste précédente"
    var nextLabel = "Piste suivante"
    var onSelect: () -> Void

    @State private var lastAngle: Double?
    @State private var accumulated = 0.0
    @State private var travel: CGFloat = 0
    @State private var rotated = false
    @State private var pressed: ClickWheelGeometry.Zone?
    @State private var fingerAngle = 0.0
    @State private var tick = 0

    var body: some View {
        let label = BaladeurPalette.wheelLabel(dark)
        let inner = diameter * 0.38
        ZStack {
            // Anneau.
            Circle().fill(BaladeurPalette.wheel(dark))
                .overlay(Circle().strokeBorder(.black.opacity(dark ? 0.5 : 0.1), lineWidth: 0.75))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.black.opacity(0.08), .white.opacity(dark ? 0.08 : 0.9)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1).padding(1))
                .shadow(color: .black.opacity(dark ? 0.35 : 0.1), radius: 1, y: -0.5)
            if let pressed {
                // Zone enfoncée : léger assombrissement d'un quart d'anneau.
                Circle().trim(from: 0, to: 0.25)
                    .stroke(.black.opacity(dark ? 0.35 : 0.07), lineWidth: (diameter - inner) / 2)
                    .rotationEffect(.degrees(pressed.startDegrees))
                    .padding((diameter - inner) / 4)
            }
            // Repère de cran sous le doigt.
            if lastAngle != nil && rotated {
                Circle().fill(BaladeurPalette.accent.opacity(0.5))
                    .frame(width: diameter * 0.05, height: diameter * 0.05)
                    .scaleEffect(tick.isMultiple(of: 2) ? 1 : 1.5)
                    .offset(y: -(diameter + inner) / 4)
                    .rotationEffect(.degrees(fingerAngle))
                    .animation(.easeOut(duration: 0.12), value: tick)
            }
            // Libellés.
            Text("MENU").font(.system(size: diameter * 0.075, weight: .bold)).tracking(0.5)
                .offset(y: -(diameter + inner) / 4 + 1)
            Image(systemName: "playpause.fill").font(.system(size: diameter * 0.075))
                .offset(y: (diameter + inner) / 4)
            Image(systemName: "backward.end.alt.fill").font(.system(size: diameter * 0.07))
                .offset(x: -(diameter + inner) / 4)
            Image(systemName: "forward.end.alt.fill").font(.system(size: diameter * 0.07))
                .offset(x: (diameter + inner) / 4)
        }
        .foregroundStyle(label)
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(dragGesture)
        .overlay {
            Button(action: onSelect) {
                Circle().fill(BaladeurPalette.body(dark))
                    .overlay(Circle().strokeBorder(.black.opacity(dark ? 0.4 : 0.12), lineWidth: 0.75))
                    .shadow(color: .black.opacity(dark ? 0.4 : 0.15), radius: 2, y: 1)
                    .frame(width: inner, height: inner)
                    .contentShape(Circle())
            }
            .buttonStyle(WheelCenterStyle())
            .help("Sélectionner")
            .accessibilityLabel("Bouton central, sélectionner")
        }
        .accessibilityElement(children: .contain)
        .accessibilityRepresentation {
            // VoiceOver : la molette est un réglable et chaque zone un bouton.
            VStack {
                Slider(value: .constant(0.5)) { Text("Molette") }
                    .accessibilityLabel("Molette")
                    .accessibilityHint("Tourner pour régler le volume ou parcourir la liste")
                    .accessibilityAdjustableAction { direction in
                        onRotate(direction == .increment ? 1 : -1)
                    }
                Button("Menu, retour", action: onMenu)
                Button("Lecture ou pause", action: onPlayPause)
                Button(previousLabel, action: onPrevious)
                Button(nextLabel, action: onNext)
                Button("Bouton central, sélectionner", action: onSelect)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                let angle = KnobGeometry.angle(of: value.location, around: center)
                travel = max(travel, hypot(value.translation.width, value.translation.height))
                guard let last = lastAngle else {
                    lastAngle = angle
                    fingerAngle = angle
                    pressed = ClickWheelGeometry.zone(forAngle: angle)
                    return
                }
                accumulated += KnobGeometry.delta(from: last, to: angle)
                lastAngle = angle
                fingerAngle = angle
                let (steps, rest) = ClickWheelGeometry.notches(in: accumulated)
                if steps != 0 {
                    accumulated = rest
                    rotated = true
                    pressed = nil
                    tick += 1
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    onRotate(steps)
                }
            }
            .onEnded { value in
                if !rotated && travel < 6 {
                    let center = CGPoint(x: diameter / 2, y: diameter / 2)
                    switch ClickWheelGeometry.zone(forAngle: KnobGeometry.angle(of: value.location, around: center)) {
                    case .menu: onMenu()
                    case .playPause: onPlayPause()
                    case .previous: onPrevious()
                    case .next: onNext()
                    }
                }
                lastAngle = nil
                accumulated = 0
                travel = 0
                rotated = false
                withAnimation(.easeOut(duration: 0.15)) { pressed = nil }
            }
    }
}

private extension ClickWheelGeometry.Zone {
    /// Début du quart d'anneau (repère de `trim`, 0° = à droite).
    var startDegrees: Double {
        switch self {
        case .menu: -135
        case .next: -45
        case .playPause: 45
        case .previous: 135
        }
    }
}

private struct WheelCenterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

// MARK: - Fenêtre principale

struct BaladeurMainView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            // Boîtier aux proportions d'un baladeur (≈ 0,6), à la hauteur de la fenêtre.
            let width = min(geo.size.width - 60, (geo.size.height - 56) / 1.62, 470)
            BaladeurDevice(width: width)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(BaladeurPalette.window(scheme == .dark).ignoresSafeArea())
    }
}

// MARK: - Mini-lecteur

struct BaladeurMiniPlayer: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 8) {
            BaladeurDevice(width: 176, compact: true)
            MiniPlayerFooter()
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 212)
        .background(BaladeurPalette.window(scheme == .dark))
    }
}
