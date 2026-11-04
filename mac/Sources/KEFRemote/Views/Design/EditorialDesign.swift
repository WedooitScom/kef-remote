import KEFKit
import SwiftUI

// Design « Éditorial » : fond clair chaud (sombre cohérent), grande typographie,
// grille à filets fins, un seul accent orange KEF.

enum EditorialPalette {
    static let paper = Color.dynamic(light: 0xF4F1EA, dark: 0x161513)
    static let ink = Color.dynamic(light: 0x141414, dark: 0xEDE8DE)
    static let muted = Color.dynamic(light: 0x6E695F, dark: 0x9B958A)
    static let rule = Color.dynamic(light: 0xCFC9BD, dark: 0x3A3732)
    static let orange = Color(hex: 0xE35205)
}

/// Filet de 1 px.
private struct Rule: View {
    var vertical = false

    var body: some View {
        Rectangle().fill(EditorialPalette.rule)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Petites capitales espacées (rubriques).
private struct Kicker: View {
    let text: String
    var color: Color = EditorialPalette.muted
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .tracking(size * 0.18)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Bouton lecture carré (noir sur clair, clair sur sombre).
private struct SquarePlayButton: View {
    let store: SpeakerStore
    var size: CGFloat = 56

    var body: some View {
        let snap = store.snapshot
        let canControl = store.status.isOnline && snap.isOn
        Button { Task { await store.playPause() } } label: {
            Image(systemName: snap.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(EditorialPalette.paper)
                .frame(width: size, height: size)
                .background(Rectangle().fill(EditorialPalette.ink))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(canControl ? 1 : 0.35)
        .disabled(!canControl)
        .help(PlayPauseText.help(snap))
        .accessibilityLabel(PlayPauseText.label(snap))
    }
}

/// Précédent / suivant (sur une radio : station précédente / suivante des favoris).
private struct SkipButtons: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 14

    var body: some View {
        let previous = model.skipPlan(.previous), next = model.skipPlan(.next)
        HStack(spacing: 14) {
            button("backward.end.fill", plan: previous) { model.skip(.previous) }
            button("forward.end.fill", plan: next) { model.skip(.next) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(EditorialPalette.ink)
    }

    private func button(_ symbol: String, plan: SkipPlan, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .opacity(plan.isEnabled ? 1 : 0.3)
        .disabled(!plan.isEnabled)
        .help(plan.help)
        .accessibilityLabel(plan.label)
    }
}

/// Sources sur une ligne de texte : « WIFI · BT · TV · OPT · COAX · AUX ».
private struct SourceLine: View {
    let store: SpeakerStore
    var size: CGFloat = 13

    var body: some View {
        let snap = store.snapshot
        HStack(spacing: size * 0.5) {
            ForEach(Array(snap.sources.enumerated()), id: \.element) { index, source in
                if index > 0 {
                    Text("·").foregroundStyle(EditorialPalette.muted).accessibilityHidden(true)
                }
                let selected = snap.isOn && snap.source == source
                Button { Task { await store.selectSource(source) } } label: {
                    Text(source.panelLabel)
                        .foregroundStyle(selected ? EditorialPalette.orange : EditorialPalette.ink)
                        .underline(selected, color: EditorialPalette.orange)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .help(source.label)
                .accessibilityLabel("Source \(source.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .font(.system(size: size, weight: .semibold))
        .tracking(size * 0.08)
        .disabled(!store.status.isOnline)
        .opacity(store.status.isOnline ? 1 : 0.4)
        .animation(.easeOut(duration: 0.2), value: snap.source)
    }
}

/// Liste numérotée des favoris : « 01  FIP », station en cours en orange avec « ● ».
private struct NumberedFavorites: View {
    @Environment(AppModel.self) private var model
    var limit: Int?
    var titleSize: CGFloat = 17
    var rowHeight: CGFloat = 44
    @State private var dropTarget: String?

    var body: some View {
        let items = Array(model.favorites.items.enumerated()).prefix(limit ?? .max)
        VStack(spacing: 0) {
            ForEach(items, id: \.element.id) { index, station in
                let current = model.isCurrent(station)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: titleSize * 0.7, weight: .medium).monospacedDigit())
                            .foregroundStyle(current ? EditorialPalette.orange : EditorialPalette.muted)
                        Text(station.title)
                            .font(.system(size: titleSize, weight: current ? .bold : .medium))
                            .tracking(-0.2)
                            .foregroundStyle(current ? EditorialPalette.orange : EditorialPalette.ink)
                            .lineLimit(1)
                        if current {
                            Text("●").font(.system(size: titleSize * 0.6)).foregroundStyle(EditorialPalette.orange)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                        if model.store.loadingStationID == station.id {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .frame(height: rowHeight - 1)
                    Rule()
                }
                .overlay(alignment: .top) {
                    if dropTarget == station.id {
                        Rectangle().fill(EditorialPalette.orange).frame(height: 2)
                    }
                }
                .contentShape(Rectangle())
                .favoriteInteractions(station: station, index: index, dropTarget: $dropTarget)
                .help(station.description ?? station.title)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(index + 1), \(station.title)" + (current ? ", en cours" : ""))
                .accessibilityAddTraits(.isButton)
            }
        }
        .animation(.spring(duration: 0.3), value: model.favorites.items)
    }
}

/// Grand chiffre de volume + filet.
private struct EditorialVolume: View {
    let store: SpeakerStore
    var numberSize: CGFloat = 44

    var body: some View {
        let snap = store.snapshot
        let enabled = store.status.isOnline && snap.isOn
        HStack(alignment: .center, spacing: 16) {
            Button { store.toggleMute() } label: {
                Kicker(text: snap.isMuted ? "Muet" : "Volume", color: snap.isMuted ? EditorialPalette.orange : EditorialPalette.muted)
                    .frame(width: 62, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .help(snap.isMuted ? "Rétablir le son (⌥⌘↓)" : "Couper le son (⌥⌘↓)")
            .accessibilityLabel(snap.isMuted ? "Rétablir le son" : "Couper le son")
            ThinVolumeSlider(store: store, track: EditorialPalette.rule, fill: EditorialPalette.ink, thickness: 1, knob: 9)
            Text("\(snap.volume)")
                .font(.system(size: numberSize, weight: .bold).monospacedDigit())
                .tracking(-1.5)
                .foregroundStyle(enabled ? EditorialPalette.ink : EditorialPalette.rule)
                .contentTransition(.numericText(value: Double(snap.volume)))
                .frame(minWidth: numberSize * 1.35, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Fenêtre principale

struct EditorialMainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let store = model.store
        GeometryReader { geo in
            let wide = geo.size.width >= 780
            // Hauteur courte : titre et pochette plus petits pour que le lecteur tienne.
            let short = geo.size.height < 600
            VStack(spacing: 0) {
                header
                Rule()
                if store.status == .notConfigured {
                    ScrollView { SetupCard().padding(28) }
                } else if wide {
                    HStack(spacing: 0) {
                        ViewThatFits(in: .vertical) {
                            nowPlaying(short: short)
                            ScrollView { nowPlaying(short: true) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        Rule(vertical: true)
                        radios
                            .frame(width: min(340, geo.size.width * 0.4))
                    }
                    Rule()
                    sourceBar
                } else {
                    // Fenêtre étroite : une colonne qui défile (lecteur, sources, radios).
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            nowPlaying(short: true)
                            Rule()
                            sourceBar
                            Rule()
                            radioList
                                .padding(.horizontal, 28)
                                .padding(.top, 22)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(EditorialPalette.paper.ignoresSafeArea())
        .foregroundStyle(EditorialPalette.ink)
    }

    private var sourceBar: some View {
        HStack(spacing: 20) {
            Kicker(text: "Source")
            SourceLine(store: model.store)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(height: 50)
    }

    private var header: some View {
        let store = model.store
        return HStack(spacing: 14) {
            Text("KEF REMOTE").font(.system(size: 12, weight: .heavy)).tracking(2.5)
            Rule(vertical: true).frame(height: 16)
            Text(model.speakerTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                .layoutPriority(-1)
            if model.isDemo {
                Kicker(text: "Démo", color: EditorialPalette.orange, size: 9)
            }
            Spacer()
            HStack(spacing: 6) {
                StatusDot(status: store.status)
                Kicker(text: store.status.isOnline ? (store.snapshot.modelLabel ?? "Connectée") : store.status.label)
                if case .offline = store.status {
                    Button("Réessayer") { store.retryNow() }.buttonStyle(.link).font(.caption)
                }
            }
            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 14, weight: .medium)).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Réglages (⌘,)")
            .accessibilityLabel("Réglages")
            powerButton(size: 28)
        }
        .padding(.leading, 28)
        .padding(.trailing, 22)
        .frame(height: 46)
    }

    private func powerButton(size: CGFloat) -> some View {
        let store = model.store
        let on = store.snapshot.isOn
        return Button { Task { await store.togglePower() } } label: {
            Image(systemName: "power")
                .font(.system(size: size * 0.45, weight: .bold))
                .frame(width: size, height: size)
                .foregroundStyle(on ? EditorialPalette.paper : EditorialPalette.ink)
                .background(Rectangle().fill(on ? EditorialPalette.orange : .clear))
                .overlay(Rectangle().strokeBorder(on ? EditorialPalette.orange : EditorialPalette.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.status.isOnline)
        .opacity(store.status.isOnline ? 1 : 0.4)
        .help(on ? "Mettre en veille" : "Allumer")
        .accessibilityLabel(on ? "Mettre en veille" : "Allumer")
    }

    private func nowPlaying(short: Bool) -> some View {
        let store = model.store
        let snap = store.snapshot
        return VStack(alignment: .leading, spacing: 0) {
            Kicker(text: NowPlayingText.kicker(model), color: EditorialPalette.orange, size: 11)
                .padding(.bottom, short ? 8 : 12)
            Text(NowPlayingText.title(model))
                .font(.system(size: short ? 40 : 54, weight: .heavy))
                .tracking(short ? -1.4 : -2)
                .lineSpacing(-6)
                .lineLimit(short ? 2 : 3)
                .minimumScaleFactor(0.55)
                .contentTransition(.opacity)
            Text(NowPlayingText.subtitle(model))
                .font(.system(size: 20, weight: .regular))
                .tracking(-0.3)
                .foregroundStyle(EditorialPalette.muted)
                .lineLimit(2)
                .padding(.top, 8)
            Spacer(minLength: 16)
            HStack(alignment: .bottom, spacing: 22) {
                CoverArtwork(snapshot: snap, cornerRadius: 0)
                    .frame(width: short ? 96 : 128, height: short ? 96 : 128)
                VStack(alignment: .leading, spacing: 14) {
                    progress
                    HStack(spacing: 18) {
                        SquarePlayButton(store: store)
                        SkipButtons()
                    }
                }
                Spacer(minLength: 0)
            }
            Rule().padding(.vertical, short ? 12 : 18)
            EditorialVolume(store: store, numberSize: short ? 36 : 44)
        }
        .padding(.horizontal, 28)
        .padding(.top, short ? 18 : 26)
        .padding(.bottom, short ? 14 : 20)
        .animation(.easeInOut(duration: 0.25), value: snap.player.title)
    }

    @ViewBuilder private var progress: some View {
        let store = model.store
        let snap = store.snapshot
        if let duration = snap.player.durationMs, !snap.player.isLive, snap.isOn {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let position = store.estimatedPosition(at: context.date) ?? 0
                let fraction = duration > 0 ? min(1, Double(position) / Double(duration)) : 0
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(EditorialPalette.rule).frame(height: 1)
                            Rectangle().fill(EditorialPalette.ink).frame(width: max(1, geo.size.width * fraction), height: 1)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: 220, height: 3)
                    Text("\(formatTime(position)) / \(formatTime(duration))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(EditorialPalette.muted)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Progression")
        }
        // Radio : « EN DIRECT » figure déjà dans la rubrique au-dessus du titre.
    }

    private var radiosHeader: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Radios").font(.system(size: 24, weight: .heavy)).tracking(-0.8)
                Spacer()
                CurrentFavoriteButton(size: 14)
                FavoritesMenu(size: 14)
            }
            .padding(.bottom, 12)
            SearchField(text: $model.searchText, isSearching: model.isSearching)
        }
    }

    /// Radios sans défilement propre (colonne unique qui défile en entier).
    private var radioList: some View {
        VStack(alignment: .leading, spacing: 0) {
            radiosHeader
            RadioContent { NumberedFavorites() }
                .padding(.top, 6)
        }
    }

    private var radios: some View {
        VStack(alignment: .leading, spacing: 0) {
            radiosHeader
            ScrollView {
                RadioContent { NumberedFavorites() }
                    .padding(.top, 6)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }
}

// MARK: - Mini-lecteur

struct EditorialMiniPlayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("KEF REMOTE").font(.system(size: 10, weight: .heavy)).tracking(2)
                StatusDot(status: store.status)
                Text(model.speakerTitle).font(.system(size: 11, weight: .medium)).foregroundStyle(EditorialPalette.muted).lineLimit(1)
                Spacer()
                OpenMainWindowButton {
                    Image(systemName: "macwindow").font(.system(size: 12, weight: .medium)).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                Button { Task { await store.togglePower() } } label: {
                    Image(systemName: "power").font(.system(size: 11, weight: .bold)).frame(width: 24, height: 24)
                        .foregroundStyle(store.snapshot.isOn ? EditorialPalette.paper : EditorialPalette.ink)
                        .background(Rectangle().fill(store.snapshot.isOn ? EditorialPalette.orange : .clear))
                        .overlay(Rectangle().strokeBorder(store.snapshot.isOn ? EditorialPalette.orange : EditorialPalette.ink, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.status.isOnline)
                .help(store.snapshot.isOn ? "Mettre en veille" : "Allumer")
                .accessibilityLabel(store.snapshot.isOn ? "Mettre en veille" : "Allumer")
            }
            Rule()
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: NowPlayingText.kicker(model), color: EditorialPalette.orange, size: 9)
                Text(NowPlayingText.compactTitle(model))
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.9)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(NowPlayingText.compactSubtitle(model))
                    .font(.system(size: 13))
                    .foregroundStyle(EditorialPalette.muted)
                    .lineLimit(1)
            }
            HStack(spacing: 14) {
                SquarePlayButton(store: store, size: 40)
                SkipButtons(size: 12)
                Spacer()
            }
            EditorialVolume(store: store, numberSize: 30)
            Rule()
            SourceLine(store: store, size: 11)
            if !model.favorites.items.isEmpty {
                Rule()
                NumberedFavorites(limit: 6, titleSize: 13, rowHeight: 28)
            }
            MiniPlayerFooter(uppercase: true)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(EditorialPalette.muted)
        }
        .padding(16)
        .frame(width: 320)
        .background(EditorialPalette.paper)
        .foregroundStyle(EditorialPalette.ink)
    }
}
