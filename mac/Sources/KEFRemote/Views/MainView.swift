import KEFKit
import SwiftUI

/// Fenêtre principale : lecteur à gauche, sources et radios à droite ; une seule colonne
/// (lecteur compact en tête) quand la fenêtre est étroite. L'en-tête de l'enceinte reste
/// fixe au-dessus de la zone qui défile (jamais sous la barre de titre).
struct MainView: View {
    @Environment(AppModel.self) private var model

    /// Largeur à partir de laquelle on passe à deux colonnes.
    static let twoColumnWidth: CGFloat = 780

    var body: some View {
        let store = model.store
        GeometryReader { geo in
            let wide = geo.size.width >= Self.twoColumnWidth
            Group {
                if wide {
                    HStack(spacing: 0) {
                        NowPlayingPanel(available: geo.size.height)
                            .frame(width: min(360, geo.size.width * 0.38))
                            .padding(.horizontal, 30)
                            .padding(.vertical, 18)

                        Rectangle().fill(.primary.opacity(0.08)).frame(width: 1).padding(.vertical, 24)

                        VStack(alignment: .leading, spacing: 0) {
                            SpeakerHeader()
                                .padding(.horizontal, 28)
                                .padding(.top, 14)
                                .padding(.bottom, 12)
                            ScrollView { sidebar.padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 28) }
                                .scrollIndicators(.automatic)
                        }
                        .frame(minWidth: 380)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        SpeakerHeader(compact: true)
                            .padding(.horizontal, 22)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if store.status != .notConfigured {
                                    CompactNowPlaying(width: geo.size.width - 44)
                                }
                                sidebar
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 6)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.automatic)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background {
            ZStack {
                VisualEffectBackground()
                Backdrop(cover: store.snapshot.isOn ? (store.snapshot.player.coverURL ?? store.snapshot.player.station?.icon) : nil)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private var sidebar: some View {
        let store = model.store
        VStack(alignment: .leading, spacing: 26) {
            if store.status == .notConfigured {
                SetupCard()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Source").font(.title3.weight(.semibold))
                    SourcePicker(store: store)
                }
                RadioSection()
            }
        }
    }
}

/// Lecteur en une colonne (fenêtre étroite) : pochette moyenne, textes, transport, volume.
struct CompactNowPlaying: View {
    @Environment(AppModel.self) private var model
    let width: CGFloat

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let side = max(120, min(width * 0.42, 200))
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                CoverArtwork(snapshot: snap, cornerRadius: 14)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(NowPlayingText.title(model))
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                    Text(NowPlayingText.subtitle(model))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    PlaybackProgress(store: store)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 18) {
                TransportControls(size: 38)
                VolumeControl(store: store)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.primary.opacity(0.05)))
    }
}

/// Pochette floutée en fond (teinte la fenêtre selon la musique).
struct Backdrop: View {
    let cover: String?

    var body: some View {
        ZStack {
            if let cover {
                RemoteImage(source: cover) { Color.clear }
                    .scaleEffect(1.4)
                    .blur(radius: 110, opaque: true)
                    .saturation(1.3)
                    .opacity(0.32)
                    .id(cover)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: cover)
        .allowsHitTesting(false)
        .clipped()
    }
}

struct NowPlayingPanel: View {
    @Environment(AppModel.self) private var model
    /// Hauteur disponible : la pochette rétrécit pour que tout tienne.
    var available: CGFloat = 640

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let roomy = available > 560
        let side = max(110, min(300, available - (roomy ? 330 : 280)))
        VStack(spacing: roomy ? 22 : 14) {
            Spacer(minLength: 0)
            CoverArtwork(snapshot: snap)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                .frame(width: side, height: side)

            VStack(spacing: 5) {
                Text(NowPlayingText.title(model))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Text(NowPlayingText.subtitle(model))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let album = snap.player.album, snap.isOn, snap.source == .wifi {
                    Text(album).font(.callout).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.25), value: snap.player.title)

            PlaybackProgress(store: store)
                .frame(maxWidth: 300)
                .frame(minHeight: 22)

            TransportControls()
            VolumeControl(store: store).frame(maxWidth: 300)
            Spacer(minLength: 0)
        }
    }
}

/// Nom de l'enceinte, état de connexion, alimentation.
struct SpeakerHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    var compact = false

    var body: some View {
        let store = model.store
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.speakerTitle).font((compact ? Font.title2 : .title).weight(.bold)).lineLimit(1)
                    if model.isDemo {
                        Text("DÉMO").font(.caption2.weight(.bold)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.kefAccent.opacity(0.18)))
                            .foregroundStyle(Color.kefAccent)
                    }
                }
                HStack(spacing: 6) {
                    StatusDot(status: store.status)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    if case .offline = store.status {
                        Button("Réessayer") { store.retryNow() }.buttonStyle(.link).font(.callout)
                    }
                }
            }
            Spacer(minLength: 8)
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(CircleIconButtonStyle(size: compact ? 28 : 32))
                .help("Réglages (⌘,)")
                .accessibilityLabel("Réglages")
            PowerButton(store: store, size: compact ? 32 : 38)
        }
    }

    private var subtitle: String {
        let store = model.store
        guard store.status.isOnline else { return store.status.label }
        let parts = [store.snapshot.modelLabel, store.snapshot.isOn ? nil : String(localized: "en veille"), model.isDemo ? nil : model.host]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// Premier lancement : aucune enceinte configurée.
struct SetupCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Connectez votre enceinte", systemImage: "hifispeaker.2").font(.headline)
            Text("KEF Remote cherche les enceintes KEF sur le réseau local. Vous pouvez aussi saisir leur adresse IP dans les réglages.")
                .font(.callout).foregroundStyle(.secondary)
            if model.discovery.kefSpeakers.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.discovery.error ?? String(localized: "Recherche en cours…")).font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(model.discovery.kefSpeakers) { speaker in
                HStack {
                    Image(systemName: "hifispeaker.fill").foregroundStyle(Color.kefAccent)
                    VStack(alignment: .leading) {
                        Text(speaker.name).font(.body.weight(.medium))
                        Text(verbatim: [speaker.model, speaker.host].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Utiliser") {
                        if let host = speaker.host { try? model.setHost(host) }
                    }
                    .disabled(speaker.host == nil)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
            }
            Button("Saisir une adresse IP…") { openSettings() }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial))
    }
}

/// Messages éphémères (import, erreurs de commande).
struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let message = model.toast ?? model.store.commandError
        ZStack {
            if let message {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { model.toast = nil; model.store.commandError = nil }
            }
        }
        .padding(.bottom, 18)
        .animation(.spring(duration: 0.35), value: message)
        .task(id: model.store.commandError) {
            guard model.store.commandError != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            model.store.commandError = nil
        }
    }
}
