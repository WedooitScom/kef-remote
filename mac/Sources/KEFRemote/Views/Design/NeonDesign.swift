import AppKit
import KEFKit
import SwiftUI

// Design « Néon 80 » : une affiche synthwave des années 80 dessinée en code. Coucher de
// soleil rayé derrière la pochette, skyline art déco et palmiers en silhouette, grille en
// perspective qui défile sur un sol brillant où le soleil se reflète, néons rose et cyan.
// Titre en lettrage chromé (dégradé argent → rose, contour, lueur). La nuit (mode sombre)
// est indigo et les néons intenses ; le jour (mode clair), c'est l'« heure dorée » pastel.
// Aucune référence à une œuvre existante : seulement l'ambiance.
//
// Sobriété : la scène est un dessin statique (redessiné au changement de taille). Pendant la
// lecture, fenêtre visible et sans « Réduire les animations », seules les lignes de la grille
// défilent, animées par Core Animation (le serveur de rendu, pas l'app : ~0 % de CPU) ; les
// néons vacillent par brèves salves espacées de quelques secondes.

// MARK: - Palette

struct NeonPalette {
    let dark: Bool

    static func of(_ scheme: ColorScheme) -> NeonPalette { NeonPalette(dark: scheme == .dark) }

    static let pink = Color(Synthwave.hotPink)
    static let magenta = Color(Synthwave.magenta)
    static let cyan = Color(Synthwave.cyan)
    static let sun = Color(Synthwave.sun)
    static let orange = Color(Synthwave.orange)
    static let violet = Color(Synthwave.violet)
    static let night = Color(Synthwave.night)

    // Sur le ciel (en-tête, bandeau d'état, texte à côté de la pochette).
    var onSky: Color { dark ? .white : Color(hex: 0x2B1055) }
    var onSkySecondary: Color { dark ? Color(hex: 0xE4D6FF).opacity(0.85) : Color(hex: 0x4A1673).opacity(0.85) }
    var kicker: Color { dark ? Self.cyan : Color(hex: 0x5A189A) }
    var kickerGlow: Color { dark ? Self.cyan : .white }

    // Sur le sol (toujours nocturne, dans les deux apparences).
    var onFloor: Color { .white }
    var onFloorSecondary: Color { Color(hex: 0xFFD3EE) }

    // Panneaux (favoris, mini-lecteur).
    var panel: Color { dark ? Color(hex: 0x100722).opacity(0.86) : Color(hex: 0xFFF6F2).opacity(0.88) }
    var text: Color { dark ? .white : Color(hex: 0x2B1055) }
    var secondary: Color { dark ? Color(hex: 0xC4B2EC) : Color(hex: 0x6E5491) }
    var accent: Color { dark ? Self.cyan : Color(hex: 0xC8156E) }
    /// Néon des titres de panneau (rose vif la nuit, framboise lisible le jour).
    var neonTitle: Color { dark ? Self.magenta : Color(hex: 0xC8156E) }
    var rowHover: Color { dark ? .white.opacity(0.06) : Color(hex: 0x7B2FF7).opacity(0.07) }

    /// Fond du mini-lecteur.
    var background: LinearGradient {
        dark ? LinearGradient(colors: [Color(hex: 0x0C0620), Color(hex: 0x1B0F3A)], startPoint: .top, endPoint: .bottom)
             : LinearGradient(colors: [Color(hex: 0xFFF1EA), Color(hex: 0xF4E4FA)], startPoint: .top, endPoint: .bottom)
    }

    /// Couleurs dépendant de l'apparence pour le thème injecté (`DesignTheme.neon`).
    enum Dynamic {
        static let accent = Color.dynamic(light: 0xC8156E, dark: 0x22E4F2)
        static let favorite = Color.dynamic(light: 0xD81B7A, dark: 0xFFC861)
        static let field = Color.dynamic(light: 0xFFFFFF, dark: 0x1E1240)
        static let fieldStroke = Color.dynamic(light: 0xEAB8D8, dark: 0x5A2DA8)
    }
}

extension View {
    /// Lueur de néon : halo serré et halo large.
    func neonGlow(_ color: Color, radius: CGFloat = 6, intensity: Double = 1) -> some View {
        shadow(color: color.opacity(0.9 * intensity), radius: radius * 0.35)
            .shadow(color: color.opacity(0.55 * intensity), radius: radius)
    }
}

// MARK: - Lettrage chromé

/// Titre « affiche des années 80 » : capitales grasses, condensées et italiques, dégradé
/// chromé (ciel argenté, ligne d'horizon sombre, reflet rose), contour indigo et lueur.
struct ChromeText: View {
    let text: String
    var size: CGFloat
    var alignment: TextAlignment = .center
    var glow: Color = NeonPalette.magenta

    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .black).italic().width(.condensed) }

    static let chrome = LinearGradient(stops: [
        .init(color: Color(hex: 0xFFFFFF), location: 0),
        .init(color: Color(hex: 0xD3DDF6), location: 0.36),
        .init(color: Color(hex: 0x8C93C9), location: 0.5),
        .init(color: Color(hex: 0x2E1F6B), location: 0.53),
        .init(color: Color(hex: 0x7A3FC4), location: 0.64),
        .init(color: Color(hex: 0xFF8FD0), location: 0.84),
        .init(color: Color(hex: 0xFFE8F6), location: 1),
    ], startPoint: .top, endPoint: .bottom)

    var body: some View {
        let outline = max(1, size * 0.04)
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                label.foregroundStyle(Color(hex: 0x1B0F3A))
                    .offset(x: cos(a) * outline, y: sin(a) * outline)
            }
            label.foregroundStyle(Self.chrome)
            // Reflet blanc au sommet des lettres.
            label.foregroundStyle(LinearGradient(colors: [.white.opacity(0.85), .clear],
                                                 startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)))
        }
        .compositingGroup()
        .shadow(color: glow.opacity(0.8), radius: size * 0.12)
        .shadow(color: glow.opacity(0.45), radius: size * 0.4)
        .accessibilityElement()
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }

    private var label: some View {
        Text(text.uppercased())
            .font(Self.font(size))
            .tracking(size * 0.02)
            .multilineTextAlignment(alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .padding(.horizontal, size * 0.12)
    }
}

// MARK: - Boutons néon

/// Bouton rond en tube de néon : contour lumineux, qui s'illumine au survol.
struct NeonButtonStyle: ButtonStyle {
    var color: Color = NeonPalette.cyan
    var size: CGFloat = 36
    /// Disque plein (lecture) : dégradé rose → violet, double anneau.
    var filled = false
    /// Allumé (source active, favori, sourdine…).
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        NeonButtonBody(configuration: configuration, color: color, size: size, filled: filled, active: active)
    }
}

private struct NeonButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let size: CGFloat
    let filled: Bool
    let active: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let lit = isEnabled && (hovering || active || filled)
        let fill: AnyShapeStyle = filled
            ? AnyShapeStyle(LinearGradient(colors: [NeonPalette.magenta, Color(hex: 0x7B2FF7)], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(color.opacity(active ? 0.55 : (hovering && isEnabled ? 0.2 : 0.07)))
        configuration.label
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(filled || active ? Color.white : color)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(filled ? Color.white.opacity(0.85) : color, lineWidth: max(1.2, size * 0.045)))
            .overlay {
                if filled {
                    Circle().strokeBorder(NeonPalette.cyan, lineWidth: 1.5).padding(-size * 0.1)
                }
            }
            .shadow(color: color.opacity(isEnabled ? (lit ? 0.95 : 0.45) : 0), radius: lit ? size * 0.16 : size * 0.08)
            .shadow(color: color.opacity(lit ? 0.5 : 0), radius: size * 0.4)
            .scaleEffect(configuration.isPressed ? 0.92 : (hovering && isEnabled ? 1.05 : 1))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Puce en néon (sources, réessayer) : capsule lumineuse, pleine quand elle est active.
private struct NeonChipStyle: ButtonStyle {
    var color: Color
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        NeonChipBody(configuration: configuration, color: color, active: active)
    }
}

private struct NeonChipBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let active: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .foregroundStyle(active ? Color.white : color)
            .background(Capsule().fill(color.opacity(active ? 0.6 : (hovering && isEnabled ? 0.18 : 0.06))))
            .overlay(Capsule().strokeBorder(color, lineWidth: 1.2))
            .shadow(color: color.opacity(isEnabled ? (active || hovering ? 0.9 : 0.35) : 0), radius: active || hovering ? 5 : 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Commandes

/// Précédent / lecture-pause / suivant en tubes de néon.
private struct NeonTransport: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 56
    /// Néon de précédent / suivant (cyan sur la nuit, violet sur fond clair).
    var tint: Color = NeonPalette.cyan

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let canControl = store.status.isOnline && snap.isOn
        let previous = model.skipPlan(.previous), next = model.skipPlan(.next)
        HStack(spacing: size * 0.34) {
            Button { model.skip(.previous) } label: { Image(systemName: "backward.fill") }
                .buttonStyle(NeonButtonStyle(color: tint, size: size * 0.7))
                .disabled(!previous.isEnabled)
                .help(previous.help)
                .accessibilityLabel(previous.label)

            Button { Task { await store.playPause() } } label: {
                Image(systemName: snap.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: snap.isPlaying ? 0 : size * 0.03)
            }
            .buttonStyle(NeonButtonStyle(color: NeonPalette.magenta, size: size, filled: true))
            .disabled(!canControl)
            .help(PlayPauseText.help(snap))
            .accessibilityLabel(PlayPauseText.label(snap))

            Button { model.skip(.next) } label: { Image(systemName: "forward.fill") }
                .buttonStyle(NeonButtonStyle(color: tint, size: size * 0.7))
                .disabled(!next.isEnabled)
                .help(next.help)
                .accessibilityLabel(next.label)
        }
    }
}

/// Bouton marche / veille.
private struct NeonPowerButton: View {
    let store: SpeakerStore
    var size: CGFloat = 28

    var body: some View {
        let on = store.snapshot.isOn
        Button { Task { await store.togglePower() } } label: { Image(systemName: "power") }
            .buttonStyle(NeonButtonStyle(color: NeonPalette.pink, size: size, active: on))
            .disabled(!store.status.isOnline)
            .help(on ? "Mettre en veille (⇧⌘P)" : "Allumer (⇧⌘P)")
            .accessibilityLabel(on ? "Mettre en veille" : "Allumer")
    }
}

/// Volume façon égaliseur : barres néon de plus en plus hautes, du cyan au rose puis à
/// l'orange. Le curseur fin transparent par-dessus gère glisser, molette, flèches et VoiceOver.
private struct NeonVolume: View {
    let store: SpeakerStore
    var bars = 18
    var height: CGFloat = 22
    var showsValue = true
    /// Néon du haut-parleur et de la valeur (cyan sur la nuit, violet sur fond clair).
    var tint: Color = NeonPalette.cyan

    var body: some View {
        let snap = store.snapshot
        let enabled = store.status.isOnline && snap.isOn
        HStack(spacing: 9) {
            Button { store.toggleMute() } label: {
                Image(systemName: snap.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentTransition(.symbolEffect(.replace))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(snap.isMuted ? NeonPalette.pink : tint)
            .neonGlow(snap.isMuted ? NeonPalette.pink : tint, radius: 5, intensity: enabled ? 0.8 : 0)
            .help(snap.isMuted ? "Rétablir le son" : "Couper le son")
            .accessibilityLabel(snap.isMuted ? "Rétablir le son" : "Couper le son")

            ZStack {
                NeonEqualizer(level: Double(snap.volume) / 100, bars: bars, lit: enabled, muted: snap.isMuted)
                    .padding(.vertical, 3)
                ThinVolumeSlider(store: store, track: .clear, fill: .clear, thickness: 1, knob: height)
            }
            .frame(height: height + 6)

            if showsValue {
                Text("\(snap.volume)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .neonGlow(tint, radius: 4, intensity: enabled ? 0.7 : 0)
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}

/// Barres de l'égaliseur (dessin seul).
private struct NeonEqualizer: View {
    var level: Double
    var bars: Int
    var lit: Bool
    var muted: Bool

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, bars)
            let gap = max(1.5, size.width / CGFloat(n) * 0.3)
            let bw = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let on = Int((level * Double(n)).rounded())
            for i in 0..<n {
                let f = Double(i + 1) / Double(n)
                let h = size.height * (0.3 + 0.7 * f)
                let rect = CGRect(x: CGFloat(i) * (bw + gap), y: size.height - h, width: bw, height: h)
                let color = Self.color(at: f)
                let path = Path(roundedRect: rect, cornerRadius: min(1.5, bw / 3))
                if i < on && lit {
                    let tone = muted ? color.opacity(0.35) : color
                    ctx.fill(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 2.5),
                             with: .color(tone.opacity(0.3)))
                    ctx.fill(path, with: .color(tone))
                    ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: bw, height: max(1, h * 0.08))),
                             with: .color(.white.opacity(muted ? 0.15 : 0.45)))
                } else {
                    ctx.stroke(path, with: .color(color.opacity(lit ? 0.4 : 0.25)), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Cyan → bleu → violet → rose → orange le long de l'égaliseur (paliers saturés : un
    /// mélange direct cyan / rose passerait par le gris).
    private static let ramp: [SRGBColor] = [Synthwave.cyan, SRGBColor(hex: 0x3D8BFF), SRGBColor(hex: 0x9D4DFF),
                                            Synthwave.magenta, Synthwave.hotPink, Synthwave.orange]

    static func color(at f: Double) -> Color {
        let x = min(1, max(0, f)) * Double(ramp.count - 1)
        let i = min(ramp.count - 2, Int(x))
        return Color(NeonArt.mix(ramp[i], ramp[i + 1], x - Double(i)))
    }
}

/// Progression façon ligne d'horizon : filet lumineux, petit soleil en tête ; « EN DIRECT »
/// entre deux horizons pour une radio. Hauteur constante (la mise en page ne saute pas).
private struct NeonProgress: View {
    let store: SpeakerStore
    var compact = false

    var body: some View {
        let snap = store.snapshot
        Group {
            if let duration = snap.player.durationMs, !snap.player.isLive, snap.isOn {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let position = store.estimatedPosition(at: context.date) ?? 0
                    let fraction = duration > 0 ? min(1, Double(position) / Double(duration)) : 0
                    HStack(spacing: 8) {
                        if !compact { time(formatTime(position)) }
                        GeometryReader { geo in
                            let w = geo.size.width
                            ZStack(alignment: .leading) {
                                horizonLine.opacity(0.35)
                                Rectangle()
                                    .fill(LinearGradient(colors: [NeonPalette.cyan, NeonPalette.magenta], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(2, w * fraction), height: 2)
                                    .neonGlow(NeonPalette.magenta, radius: 4)
                                Circle().fill(NeonPalette.sun).frame(width: 7, height: 7)
                                    .neonGlow(NeonPalette.orange, radius: 5)
                                    .offset(x: max(0, min(w - 7, w * fraction - 3.5)))
                            }
                            .frame(maxHeight: .infinity)
                        }
                        if !compact { time("-" + formatTime(max(0, duration - position))) }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Progression")
            } else if snap.player.isLive && snap.isPlaying {
                // Radio en direct : deux horizons et un petit égaliseur (le bandeau dit déjà « EN DIRECT »).
                HStack(spacing: 8) {
                    horizonLine
                    EqualizerBars(animating: true, color: Color(hex: 0xFFB8E0))
                        .neonGlow(NeonPalette.magenta, radius: 5)
                    horizonLine
                }
                .accessibilityElement()
                .accessibilityLabel("En direct")
            } else {
                horizonLine.opacity(0.3)
            }
        }
        .frame(height: compact ? 12 : 16)
    }

    private var horizonLine: some View {
        LinearGradient(colors: [NeonPalette.cyan.opacity(0), NeonPalette.cyan, NeonPalette.magenta, NeonPalette.cyan, NeonPalette.cyan.opacity(0)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 1.2)
            .neonGlow(NeonPalette.magenta, radius: 3, intensity: 0.7)
    }

    private func time(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(hex: 0xBFF8FF))
            .fixedSize()
    }
}

/// Sources en puces néon.
private struct NeonSourceChips: View {
    let store: SpeakerStore
    /// Couleur des puces inactives (cyan sur la nuit, violet sur le ciel doré).
    var tint: Color = NeonPalette.cyan

    var body: some View {
        let snap = store.snapshot
        HStack(spacing: 6) {
            ForEach(snap.sources) { source in
                let selected = snap.isOn && snap.source == source
                Button { Task { await store.selectSource(source) } } label: { Text(source.panelLabel) }
                    .buttonStyle(NeonChipStyle(color: selected ? NeonPalette.magenta : tint, active: selected))
                    .help(source.label)
                    .accessibilityLabel("Source \(source.label)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .disabled(!store.status.isOnline)
        .animation(.easeOut(duration: 0.2), value: snap.source)
    }
}

// MARK: - Pochette et enseigne

/// Pochette dans un double cadre néon (cyan dedans, magenta dehors) avec halo.
private struct NeonArtworkFrame: View {
    let snapshot: SpeakerSnapshot
    var size: CGFloat

    var body: some View {
        let r = max(3, size * 0.025)
        CoverArtwork(snapshot: snapshot, cornerRadius: r)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(NeonPalette.cyan, lineWidth: max(1.5, size * 0.009)))
            .neonGlow(NeonPalette.cyan, radius: max(5, size * 0.04))
            .padding(max(4, size * 0.03))
            .overlay(RoundedRectangle(cornerRadius: r * 1.8, style: .continuous)
                .strokeBorder(NeonPalette.magenta, lineWidth: max(1.5, size * 0.011))
                .neonGlow(NeonPalette.magenta, radius: max(6, size * 0.07)))
            .background(RoundedRectangle(cornerRadius: r * 1.8, style: .continuous).fill(NeonPalette.night.opacity(0.55)))
    }
}

/// Vacillement d'un tube de néon : allumé, puis de temps en temps une brève salve de
/// baisses. Piloté par des pauses (aucune image calculée entre deux salves).
enum NeonFlicker {
    /// Boucle jusqu'à l'annulation de la tâche : attend 3 à 7 s, puis applique `levels`
    /// à 90 ms d'intervalle.
    @MainActor
    static func bursts(levels: [Double], apply: (Double) -> Void) async {
        var rng = SystemRandomNumberGenerator()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 3000...7000, using: &rng)))
            for level in levels {
                guard !Task.isCancelled else { return }
                apply(level)
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }
}

/// Enseigne « OFF » de la veille : tube éteint toujours visible, tube allumé qui vacille.
private struct NeonOffSign: View {
    var width: CGFloat
    var animating: Bool
    @State private var level = 1.0

    var body: some View {
        let font = Font.system(size: width * 0.4, weight: .heavy, design: .rounded).italic()
        let f = level
        Group {
            ZStack {
                Text("OFF").font(font).foregroundStyle(NeonPalette.pink.opacity(0.22))
                Text("OFF").font(font).foregroundStyle(Color(hex: 0xFFE1F1))
                    .neonGlow(NeonPalette.pink, radius: width * 0.06)
                    .opacity(f)
            }
            .frame(width: width, height: width * 0.62)
            .background(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous).fill(NeonPalette.night.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
                .strokeBorder(NeonPalette.cyan.opacity(0.4 + 0.6 * f), lineWidth: 1.5)
                .neonGlow(NeonPalette.cyan, radius: 6, intensity: f))
        }
        .accessibilityElement()
        .accessibilityLabel("En veille")
        .task(id: animating) {
            level = 1
            guard animating else { return }
            await NeonFlicker.bursts(levels: [0.3, 0.85, 0.2, 0.7, 1]) { level = $0 }
        }
    }
}

/// Pictogramme d'état (hors ligne, connexion) dans un cadre néon.
private struct NeonStatusSign: View {
    var symbol: String
    var size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.3, weight: .semibold))
            .foregroundStyle(NeonPalette.cyan)
            .neonGlow(NeonPalette.cyan, radius: 8)
            .frame(width: size, height: size * 0.62)
            .background(RoundedRectangle(cornerRadius: size * 0.07, style: .continuous).fill(NeonPalette.night.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .strokeBorder(NeonPalette.magenta, lineWidth: 1.5)
                .neonGlow(NeonPalette.magenta, radius: 6))
            .accessibilityHidden(true)
    }
}

// MARK: - Favoris

private struct NeonFavoritesList: View {
    @Environment(AppModel.self) private var model
    @State private var dropTarget: String?

    var body: some View {
        LazyVStack(spacing: 3) {
            ForEach(Array(model.favorites.items.enumerated()), id: \.element.id) { index, station in
                NeonFavoriteRow(station: station, index: index, dropTarget: $dropTarget)
            }
        }
        .animation(.spring(duration: 0.3), value: model.favorites.items)
    }
}

private struct NeonFavoriteRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let station: Station
    let index: Int
    @Binding var dropTarget: String?
    @State private var hovering = false

    var body: some View {
        let pal = NeonPalette.of(scheme)
        let current = model.isCurrent(station)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 10) {
            StationLogo(station: station, cornerRadius: 7)
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(current ? NeonPalette.cyan : .clear, lineWidth: 1.5))
                .neonGlow(NeonPalette.cyan, radius: 5, intensity: current ? 1 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.title)
                    .font(.system(size: 13, weight: current ? .heavy : .semibold))
                    .italic(current)
                    .lineLimit(1)
                if let d = station.description {
                    Text(d)
                        .font(.system(size: 11))
                        .foregroundStyle(pal.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if model.store.loadingStationID == station.id {
                ProgressView().controlSize(.mini)
            } else if current {
                EqualizerBars(animating: model.store.snapshot.isPlaying, color: pal.neonTitle)
            }
            if hovering {
                Button { model.toggleFavorite(station) } label: {
                    Image(systemName: "star.fill").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NeonPalette.Dynamic.favorite)
                .help("Retirer « \(station.title) » des favoris")
                .accessibilityLabel("Retirer \(station.title) des favoris")
            }
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(current ? pal.neonTitle : pal.secondary.opacity(0.8))
                    .help("⌘\(index + 1)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if current {
                shape.fill(LinearGradient(colors: [NeonPalette.magenta.opacity(pal.dark ? 0.32 : 0.16),
                                                   NeonPalette.violet.opacity(pal.dark ? 0.2 : 0.08)],
                                          startPoint: .leading, endPoint: .trailing))
            } else if hovering {
                shape.fill(pal.rowHover)
            }
        }
        .overlay {
            if current {
                shape.strokeBorder(NeonPalette.magenta.opacity(0.75), lineWidth: 1)
            }
            if dropTarget == station.id {
                shape.strokeBorder(pal.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .favoriteInteractions(station: station, index: index, dropTarget: $dropTarget)
        .help(station.description ?? station.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(station.title + (current ? ", en cours" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Retirer des favoris") { model.toggleFavorite(station) }
    }
}

/// Panneau des favoris : verre nocturne (ou nacré le jour) bordé d'un néon dégradé.
private struct NeonFavoritesPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        let pal = NeonPalette.of(scheme)
        let current = model.store.snapshot.currentStation
        let favorite = model.favorites.contains(current)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("FAVORIS")
                    .font(.system(size: 15, weight: .black).italic().width(.expanded))
                    .foregroundStyle(pal.neonTitle)
                    .neonGlow(NeonPalette.magenta, radius: 5, intensity: pal.dark ? 0.9 : 0.35)
                if !model.favorites.items.isEmpty {
                    Text("\(model.favorites.items.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(pal.secondary)
                }
                Spacer(minLength: 4)
                Button { model.toggleExplorer() } label: { Image(systemName: "safari") }
                    .buttonStyle(NeonButtonStyle(color: pal.accent, size: 26, active: model.showsExplorer))
                    .disabled(!model.store.hasClient)
                    .help("Explorer les radios par pays, genre et langue (⌘E)")
                    .accessibilityLabel("Explorer les radios")
                Button { model.toggleCurrentFavorite() } label: { Image(systemName: favorite ? "star.fill" : "star") }
                    .buttonStyle(NeonButtonStyle(color: pal.dark ? NeonPalette.sun : Color(hex: 0xD81B7A), size: 26, active: favorite))
                    .disabled(current == nil)
                    .help(current.map { favorite ? "Retirer « \($0.title) » des favoris" : "Ajouter « \($0.title) » aux favoris" }
                          ?? "Aucune radio airable en cours")
                    .accessibilityLabel(favorite ? "Retirer la radio en cours" : "Ajouter la radio en cours")
                FavoritesMenu(size: 15)
            }
            SearchField(text: $model.searchText, isSearching: model.isSearching)
            ScrollView {
                RadioContent { NeonFavoritesList() }
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
        }
        .padding(14)
        .neonPanel(pal)
        .foregroundStyle(pal.text)
    }
}

extension View {
    /// Panneau de verre bordé d'un néon dégradé rose → violet → cyan.
    fileprivate func neonPanel(_ pal: NeonPalette, radius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(pal.panel))
            .overlay(shape.strokeBorder(LinearGradient(colors: [NeonPalette.magenta, NeonPalette.violet, NeonPalette.cyan],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.3))
            .shadow(color: NeonPalette.magenta.opacity(pal.dark ? 0.45 : 0.25), radius: 14)
    }
}

// MARK: - Visibilité de la fenêtre

/// Suit la visibilité de la fenêtre qui contient la vue (masquée, réduite, recouverte,
/// mini-lecteur fermé) : les animations s'arrêtent quand personne ne les voit.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { visible in isVisible = visible }
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = { visible in isVisible = visible }
    }

    final class ProbeView: NSView {
        var onChange: ((Bool) -> Void)?
        private var token: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            if let window {
                token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                               object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            report()
        }

        private func report() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            // Hors du cycle de mise à jour de SwiftUI.
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }

        override func removeFromSuperview() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            super.removeFromSuperview()
        }
    }
}

// MARK: - Fenêtre principale

/// Cadre (pochette ou enseigne) autour duquel la scène se construit : soleil centré
/// derrière, horizon juste dessous.
private struct NeonSunAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    fileprivate func neonSunAnchor() -> some View {
        anchorPreference(key: NeonSunAnchorKey.self, value: .bounds) { $0 }
    }
}

struct NeonMainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = true

    /// Écart entre le bas du cadre et l'horizon.
    private static let horizonGap: CGFloat = 16
    /// Largeur à partir de laquelle les favoris passent à droite.
    private static let wideWidth: CGFloat = 820

    var body: some View {
        let pal = NeonPalette.of(scheme)
        let store = model.store
        let snap = store.snapshot
        let night = !(store.status.isOnline && snap.isOn)
        // La nuit (veille, hors ligne), le ciel est sombre même en mode clair : textes clairs.
        let sky = NeonPalette(dark: pal.dark || night)
        GeometryReader { geo in
            let wide = geo.size.width >= Self.wideWidth
            let panelWidth = min(380, max(300, geo.size.width * 0.34))
            VStack(spacing: 12) {
                header(sky, wide: wide)
                if store.status == .notConfigured {
                    ScrollView { SetupCard().padding(.top, 8) }
                        .padding(14)
                        .neonPanel(pal)
                        .foregroundStyle(pal.text)
                } else if wide {
                    let heroSize = CGSize(width: geo.size.width - panelWidth - 72, height: geo.size.height - 70)
                    HStack(alignment: .top, spacing: 24) {
                        wideHero(sky, available: heroSize)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        NeonFavoritesPanel()
                            .frame(width: panelWidth)
                    }
                } else {
                    compactHero(sky, width: geo.size.width - 32, height: geo.size.height)
                    NeonFavoritesPanel()
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, wide ? 24 : 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .backgroundPreferenceValue(NeonSunAnchorKey.self) { anchor in
            GeometryReader { proxy in
                let wide = proxy.size.width >= Self.wideWidth
                let spec = anchor.map {
                    NeonSceneSpec.around(proxy[$0], in: proxy.size, dark: pal.dark, night: night, gap: Self.horizonGap,
                                         foregroundPalms: wide)
                } ?? NeonSceneSpec.fallback(proxy.size, dark: pal.dark, night: night)
                NeonBackdrop(spec: spec, animating: snap.isPlaying && windowVisible && !reduceMotion)
                    .equatable()
                    .id(night)
                    .transition(.opacity)
            }
            .ignoresSafeArea()
        }
        .background(WindowVisibilityReader(isVisible: $windowVisible))
        .foregroundStyle(sky.onSky)
        .animation(.easeInOut(duration: 0.5), value: night)
        .animation(.easeInOut(duration: 0.3), value: snap.player.title)
    }

    // MARK: En-tête

    private func header(_ pal: NeonPalette, wide: Bool) -> some View {
        let store = model.store
        return HStack(spacing: 10) {
            Circle().fill(statusColor(store.status))
                .frame(width: 8, height: 8)
                .neonGlow(statusColor(store.status), radius: 5)
                .accessibilityHidden(true)
            Text(model.speakerTitle.uppercased())
                .font(.system(size: 13, weight: .heavy).width(.expanded))
                .tracking(1.2)
                .lineLimit(1)
                .foregroundStyle(pal.onSky)
                .layoutPriority(-1)
            if model.isDemo && !RadioCatalog.fold(model.speakerTitle).contains("demo") {
                Text("DÉMO")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(pal.neonTitle)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(pal.neonTitle, lineWidth: 1))
            }
            Spacer(minLength: 8)
            if store.status.isOnline {
                if wide {
                    NeonSourceChips(store: store, tint: pal.dark ? NeonPalette.cyan : Color(hex: 0x6A1FC0))
                } else if let label = store.snapshot.modelLabel {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(pal.onSkySecondary)
                        .lineLimit(1)
                        .layoutPriority(-2)
                }
            } else {
                Text(store.status.label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(pal.onSkySecondary)
                    .lineLimit(1)
            }
            if case .offline = store.status {
                Button("RÉESSAYER") { store.retryNow() }
                    .buttonStyle(NeonChipStyle(color: NeonPalette.magenta))
            }
            Button { openSettings() } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(NeonButtonStyle(color: pal.dark ? NeonPalette.cyan : Color(hex: 0x7B2FF7), size: 26))
                .help("Réglages (⌘,)")
                .accessibilityLabel("Réglages")
            NeonPowerButton(store: store, size: 26)
        }
        .frame(height: 30)
    }

    // MARK: Lecteur (fenêtre large)

    /// Colonne d'affiche : pochette devant le soleil, titre chromé et commandes sur la grille.
    private func wideHero(_ pal: NeonPalette, available: CGSize) -> some View {
        let store = model.store
        let snap = store.snapshot
        let standby = store.status.isOnline && !snap.isOn
        let art = min(300, max(110, min(available.height - 330, available.width * 0.5)))
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            kicker(pal)
                .opacity(standby ? 0 : 1)
                .padding(.bottom, 12)
            frameView(art: art, standby: standby)
                .neonSunAnchor()
            Spacer().frame(height: Self.horizonGap + 16)
            ChromeText(text: NowPlayingText.title(model), size: art > 180 ? 40 : 32)
                .frame(maxWidth: available.width)
            Text(NowPlayingText.subtitle(model))
                .font(.system(size: 15, weight: .semibold).italic())
                .foregroundStyle(pal.onFloorSecondary)
                .neonGlow(NeonPalette.pink, radius: 5, intensity: 0.8)
                .lineLimit(1)
                .padding(.top, 2)
                .padding(.horizontal, 12)
            if standby {
                wakeButton(size: 58)
                    .padding(.top, 18)
            } else if store.status.isOnline {
                NeonProgress(store: store)
                    .frame(maxWidth: min(380, available.width * 0.8))
                    .padding(.top, 14)
                NeonTransport(size: 56)
                    .padding(.top, 12)
                NeonVolume(store: store)
                    .frame(maxWidth: min(320, available.width * 0.75))
                    .padding(.top, 12)
            } else if case .offline = store.status {
                Button("RÉESSAYER") { store.retryNow() }
                    .buttonStyle(NeonChipStyle(color: NeonPalette.magenta))
                    .padding(.top, 16)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Lecteur (fenêtre étroite)

    /// Pochette et titre côte à côte sur le ciel, commandes sur la grille, sources dessous.
    private func compactHero(_ pal: NeonPalette, width: CGFloat, height: CGFloat) -> some View {
        let store = model.store
        let snap = store.snapshot
        let standby = store.status.isOnline && !snap.isOn
        let art = min(190, max(96, min(width * 0.3, height * 0.25)))
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                frameView(art: art, standby: standby)
                    .neonSunAnchor()
                VStack(alignment: .leading, spacing: 5) {
                    if !standby { kicker(pal) }
                    ChromeText(text: NowPlayingText.title(model), size: 30, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(NowPlayingText.subtitle(model))
                        .font(.system(size: 13, weight: .semibold).italic())
                        .foregroundStyle(Color.white)
                        .shadow(color: pal.dark ? NeonPalette.pink.opacity(0.8) : Color(hex: 0x2B1055).opacity(0.9), radius: 3)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer().frame(height: Self.horizonGap - 6)
            if standby {
                HStack(spacing: 12) {
                    wakeButton(size: 44)
                }
            } else if store.status.isOnline {
                NeonProgress(store: store)
                HStack(spacing: 16) {
                    NeonTransport(size: 46)
                    NeonVolume(store: store, bars: 14, height: 18)
                        .frame(maxWidth: 230)
                }
            }
            if store.status.isOnline {
                ViewThatFits(in: .horizontal) {
                    NeonSourceChips(store: store)
                    ScrollView(.horizontal) { NeonSourceChips(store: store) }
                        .scrollIndicators(.never)
                }
            }
        }
    }

    // MARK: Briques

    /// Bandeau d'état (« EN DIRECT · WIFI ») : pastille de verre nocturne, lisible sur le soleil.
    private func kicker(_ pal: NeonPalette) -> some View {
        Text(NowPlayingText.kicker(model))
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .tracking(2.2)
            .foregroundStyle(NeonPalette.cyan)
            .neonGlow(NeonPalette.cyan, radius: 4, intensity: 0.7)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(NeonPalette.night.opacity(0.72)))
            .overlay(Capsule().strokeBorder(NeonPalette.cyan.opacity(0.55), lineWidth: 1))
    }

    /// Pochette, enseigne « OFF » ou pictogramme d'état.
    @ViewBuilder
    private func frameView(art: CGFloat, standby: Bool) -> some View {
        let store = model.store
        if standby {
            NeonOffSign(width: art, animating: windowVisible && !reduceMotion)
        } else if store.status.isOnline {
            NeonArtworkFrame(snapshot: store.snapshot, size: art)
        } else {
            NeonStatusSign(symbol: store.status == .connecting ? "antenna.radiowaves.left.and.right" : "wifi.exclamationmark",
                           size: art)
        }
    }

    /// Gros bouton d'allumage (veille).
    private func wakeButton(size: CGFloat) -> some View {
        let store = model.store
        return HStack(spacing: 12) {
            Button { Task { await store.togglePower() } } label: { Image(systemName: "power") }
                .buttonStyle(NeonButtonStyle(color: NeonPalette.pink, size: size, filled: true))
                .disabled(!store.status.isOnline)
                .help("Allumer (⇧⌘P)")
                .accessibilityLabel("Allumer")
            Text("ALLUMER")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Color(hex: 0xFFE1F1))
                .neonGlow(NeonPalette.pink, radius: 5)
        }
    }
}

/// Couleur du voyant d'état.
private func statusColor(_ status: ConnectionStatus) -> Color {
    switch status {
    case .online: Color(Synthwave.turquoise)
    case .connecting: NeonPalette.sun
    case .offline: NeonPalette.pink
    case .notConfigured: .gray
    }
}

// MARK: - Mini-lecteur

struct NeonMiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 6)

    var body: some View {
        let pal = NeonPalette.of(scheme)
        let store = model.store
        let snap = store.snapshot
        let standby = store.status.isOnline && !snap.isOn
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(statusColor(store.status)).frame(width: 7, height: 7)
                    .neonGlow(statusColor(store.status), radius: 4)
                Text(model.speakerTitle.uppercased())
                    .font(.system(size: 11, weight: .heavy).width(.expanded))
                    .tracking(0.8)
                    .lineLimit(1)
                Spacer(minLength: 4)
                OpenMainWindowButton { Image(systemName: "macwindow") }
                    .buttonStyle(NeonButtonStyle(color: pal.accent, size: 22))
            }

            card(pal, standby: standby)

            if store.status.isOnline {
                HStack(spacing: 0) {
                    if standby {
                        Text("Touchez ⏻ ou une radio")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(pal.secondary)
                    } else {
                        NeonTransport(size: 40, tint: pal.dark ? NeonPalette.cyan : Color(hex: 0x7B2FF7))
                    }
                    Spacer(minLength: 4)
                    NeonPowerButton(store: store, size: 28)
                }
                .padding(.horizontal, 2)
                if !standby {
                    NeonVolume(store: store, bars: 16, height: 15, tint: pal.dark ? NeonPalette.cyan : Color(hex: 0x7B2FF7))
                }
            }

            if !model.favorites.items.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(model.favorites.items.prefix(12)) { station in
                        let current = model.isCurrent(station)
                        Button { model.play(station) } label: {
                            StationLogo(station: station, cornerRadius: 6)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if store.loadingStationID == station.id { ProgressView().controlSize(.mini) }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(current ? NeonPalette.cyan : .clear, lineWidth: 1.5))
                                .neonGlow(NeonPalette.cyan, radius: 4, intensity: current ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                        .help(station.title)
                        .accessibilityLabel(station.title + (current ? ", en cours" : ""))
                    }
                }
            }

            MiniPlayerFooter()
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pal.secondary)
        }
        .padding(10)
        .frame(width: 240)
        .background(pal.background)
        .background(WindowVisibilityReader(isVisible: $visible))
        .foregroundStyle(pal.text)
    }

    /// Carte d'affiche : petite scène, pochette (ou enseigne) devant le soleil, titre chromé.
    private func card(_ pal: NeonPalette, standby: Bool) -> some View {
        let store = model.store
        let size = CGSize(width: 220, height: 138)
        let art: CGFloat = 62
        let artRect = CGRect(x: (size.width - art) / 2, y: 10, width: art, height: standby ? art * 0.62 : art)
        let night = !(store.status.isOnline && store.snapshot.isOn)
        let spec = NeonSceneSpec.around(artRect, in: size, dark: pal.dark, night: night, gap: 8, compact: true)
        return ZStack(alignment: .top) {
            NeonBackdrop(spec: spec, animating: store.snapshot.isPlaying && visible && !reduceMotion)
                .equatable()
            VStack(spacing: 0) {
                Group {
                    if standby {
                        NeonOffSign(width: art, animating: visible && !reduceMotion)
                    } else if store.status.isOnline {
                        NeonArtworkFrame(snapshot: store.snapshot, size: art - 6)
                    } else {
                        NeonStatusSign(symbol: "wifi.exclamationmark", size: art)
                    }
                }
                .frame(width: art, height: artRect.height)
                .padding(.top, artRect.minY)
                Spacer(minLength: 0)
                ChromeText(text: NowPlayingText.compactTitle(model), size: 17)
                    .padding(.horizontal, 6)
                Text(NowPlayingText.compactSubtitle(model))
                    .font(.system(size: 10.5, weight: .semibold).italic())
                    .foregroundStyle(pal.onFloorSecondary)
                    .neonGlow(NeonPalette.pink, radius: 3, intensity: 0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(LinearGradient(colors: [NeonPalette.magenta, NeonPalette.violet, NeonPalette.cyan],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
        .shadow(color: NeonPalette.magenta.opacity(pal.dark ? 0.5 : 0.3), radius: 8)
        .animation(.easeInOut(duration: 0.4), value: night)
    }
}

// MARK: - Vignette (sélecteur de styles)

/// Petite affiche : soleil rayé, grille, palmiers, cadre néon au centre.
struct NeonThumbnailArt: View {
    var body: some View {
        Canvas { ctx, size in
            let a = min(size.width, size.height) * 0.36
            let art = CGRect(x: (size.width - a) / 2, y: size.height * 0.12, width: a, height: a)
            let spec = NeonSceneSpec.around(art, in: size, dark: true, night: false, gap: size.height * 0.07, compact: true)
            NeonArt.drawSky(ctx, spec)
            NeonArt.drawFloor(ctx, spec)
            NeonArt.drawPalms(ctx, spec)
            let lw = max(0.75, a * 0.05)
            ctx.fill(Path(art), with: .linearGradient(Gradient(colors: [NeonPalette.magenta, Color(hex: 0x5A189A)]),
                                                     startPoint: CGPoint(x: art.minX, y: art.minY),
                                                     endPoint: CGPoint(x: art.maxX, y: art.maxY)))
            ctx.stroke(Path(art), with: .color(NeonPalette.cyan), lineWidth: lw)
            ctx.stroke(Path(art.insetBy(dx: -lw * 2, dy: -lw * 2)), with: .color(NeonPalette.magenta), lineWidth: lw)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Scène

/// Géométrie et ambiance d'une scène : soleil, horizon, jour / nuit, veille.
struct NeonSceneSpec: Equatable {
    var size: CGSize
    var sun: CGPoint
    var sunDiameter: CGFloat
    var horizon: CGFloat
    var dark: Bool
    /// Veille ou hors ligne : soleil couché, ciel nocturne, grille éteinte.
    var night: Bool
    /// Moins de détails (mini-lecteur, vignette).
    var compact = false
    /// Grands palmiers au premier plan (fenêtre large) ; sinon, plus petits, plantés sur
    /// l'horizon (ils ne passent pas derrière les commandes).
    var foregroundPalms = true

    /// Soleil centré derrière `frame` (pochette, enseigne), horizon `gap` points dessous.
    static func around(_ frame: CGRect, in size: CGSize, dark: Bool, night: Bool, gap: CGFloat,
                       compact: Bool = false, foregroundPalms: Bool = true) -> NeonSceneSpec {
        let horizon = min(size.height - 12, frame.maxY + gap)
        let d = max(frame.width, frame.height) * (night ? 1.75 : 1.55)
        let y = night ? horizon + d * 0.2 : horizon - d * 0.36
        return NeonSceneSpec(size: size, sun: CGPoint(x: frame.midX, y: y), sunDiameter: d, horizon: horizon,
                             dark: dark, night: night, compact: compact, foregroundPalms: foregroundPalms)
    }

    /// Sans cadre (aucune enceinte configurée) : soleil au centre, horizon aux trois cinquièmes.
    static func fallback(_ size: CGSize, dark: Bool, night: Bool) -> NeonSceneSpec {
        let horizon = size.height * 0.6
        let d = min(size.width, size.height) * 0.42
        return NeonSceneSpec(size: size, sun: CGPoint(x: size.width / 2, y: night ? horizon + d * 0.2 : horizon - d * 0.36),
                             sunDiameter: d, horizon: horizon, dark: dark, night: night)
    }
}

/// Fond : ciel, sol et oiseaux (statiques), lumières du sol (animées), palmiers (statiques).
struct NeonBackdrop: View, Equatable {
    let spec: NeonSceneSpec
    var animating: Bool
    /// Intensité de la ligne d'horizon (salves de vacillement).
    @State private var flicker = 1.0

    nonisolated static func == (a: Self, b: Self) -> Bool { a.spec == b.spec && a.animating == b.animating }

    var body: some View {
        // Les captures (`--snapshot`) dessinent la vue sans ses calques : grille dans le Canvas.
        let live = animating && !Snapshotter.isRequested
        let band = NeonArt.floorBand(spec)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                NeonArt.drawSky(ctx, spec)
                NeonArt.drawFloorBase(ctx, spec)
                NeonArt.drawFloorLights(ctx, spec, rows: !live, flicker: flicker)
                NeonArt.drawBirds(ctx, spec)
            }
            if live {
                NeonGridRows(spec: spec)
                    .frame(width: band.width, height: band.height)
                    .offset(y: band.minY)
            }
            Canvas { ctx, _ in NeonArt.drawPalms(ctx, spec) }
        }
        .frame(width: spec.size.width, height: spec.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: live) {
            flicker = 1
            guard live else { return }
            await NeonFlicker.bursts(levels: [0.55, 0.95, 0.7, 1]) { flicker = $0 }
        }
    }
}

/// Lignes transversales de la grille qui avancent vers soi, animées par Core Animation : un
/// calque par ligne, image clé par image clé (position et opacité), en boucle sur la période
/// où chaque ligne prend la place de la suivante. Rien n'est recalculé par l'app.
struct NeonGridRows: NSViewRepresentable {
    let spec: NeonSceneSpec

    func makeNSView(context: Context) -> RowsView { RowsView() }

    func updateNSView(_ view: RowsView, context: Context) { view.configure(spec) }

    final class RowsView: NSView {
        private var configured: NeonSceneSpec?
        private let root = CALayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            // Calque hébergé, origine en bas à gauche (repère macOS) : les ordonnées sont inversées.
            root.masksToBounds = true
            layer = root
            wantsLayer = true
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(_ s: NeonSceneSpec) {
            guard s != configured else { return }
            configured = s
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            let band = NeonArt.floorBand(s)
            let color = NSColor(NeonArt.gridColor(s)).cgColor
            let width = s.compact ? 0.7 : 1.1
            let period = 1 / NeonArt.gridSpeed
            let samples = 16
            for k in 0..<NeonArt.gridRowCount(s) {
                // Positions et opacités le long d'une période (z : k + 1 → k).
                var ys: [CGFloat] = [], alphas: [Float] = []
                for i in 0...samples {
                    let phase = Double(i) / Double(samples)
                    let y = NeonArt.gridRowY(s, depthIndex: Double(k) + 1 - phase)
                    ys.append(band.height - (min(y, s.size.height + 4) - band.minY))
                    alphas.append(Float(NeonArt.gridAlpha(s, y: y)))
                }
                let line = CALayer()
                line.bounds = CGRect(x: 0, y: 0, width: band.width, height: width)
                line.position = CGPoint(x: band.width / 2, y: ys[0])
                line.opacity = alphas[0]
                line.backgroundColor = color
                line.shadowColor = color
                line.shadowOpacity = 0.9
                line.shadowRadius = s.compact ? 1 : 2
                line.shadowOffset = .zero
                line.shadowPath = CGPath(rect: line.bounds.insetBy(dx: 0, dy: -0.5), transform: nil)
                let move = CAKeyframeAnimation(keyPath: "position.y")
                move.values = ys
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = alphas
                let group = CAAnimationGroup()
                group.animations = [move, fade]
                group.duration = period
                group.repeatCount = .infinity
                group.isRemovedOnCompletion = false
                line.add(group, forKey: "advance")
                root.addSublayer(line)
            }
            CATransaction.commit()
        }
    }
}

/// Dessin de la scène (fonctions pures : la géométrie vient de `NeonSceneSpec`).
enum NeonArt {
    // MARK: Couleurs

    static func mix(_ a: SRGBColor, _ b: SRGBColor, _ t: Double) -> SRGBColor {
        let t = min(1, max(0, t))
        return SRGBColor(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t,
                         blue: a.blue + (b.blue - a.blue) * t)
    }

    private static func c(_ hex: UInt32, _ opacity: Double = 1) -> Color { Color(hex: hex, opacity: opacity) }

    private static func skyStops(_ s: NeonSceneSpec) -> [Gradient.Stop] {
        switch (s.dark, s.night) {
        case (true, false):
            return [.init(color: c(0x07031A), location: 0), .init(color: c(0x1B0F3A), location: 0.32),
                    .init(color: c(0x4A1570), location: 0.6), .init(color: c(0xB0166E), location: 0.82),
                    .init(color: c(0xFF5A6E), location: 0.94), .init(color: c(0xFF9A4A), location: 1)]
        case (true, true):
            return [.init(color: c(0x03010B), location: 0), .init(color: c(0x110829), location: 0.5),
                    .init(color: c(0x2B1055), location: 0.85), .init(color: c(0x5A1D6E), location: 1)]
        case (false, false):
            return [.init(color: c(0x8F7DDA), location: 0), .init(color: c(0xC4A5EE), location: 0.34),
                    .init(color: c(0xFFB2CE), location: 0.66), .init(color: c(0xFFC79C), location: 0.88),
                    .init(color: c(0xFFE3A6), location: 1)]
        case (false, true):
            return [.init(color: c(0x2A2163), location: 0), .init(color: c(0x5B3F99), location: 0.55),
                    .init(color: c(0xA45C9E), location: 0.86), .init(color: c(0xE38CA2), location: 1)]
        }
    }

    private static func floorColors(_ s: NeonSceneSpec) -> [Color] {
        switch (s.dark, s.night) {
        case (true, false): [c(0x220B42), c(0x0B0421)]
        case (true, true): [c(0x100627), c(0x04020C)]
        case (false, false): [c(0x6C46AA), c(0x2C1762)]
        case (false, true): [c(0x3B2774), c(0x170B33)]
        }
    }

    // MARK: Ciel

    static func drawSky(_ context: GraphicsContext, _ s: NeonSceneSpec) {
        let w = s.size.width, h = s.size.height, hy = s.horizon, d = s.sunDiameter
        guard w > 0, h > 0, hy > 0 else { return }
        var ctx = context
        let skyRect = CGRect(x: 0, y: 0, width: w, height: hy + 1)
        ctx.clip(to: Path(skyRect))
        ctx.fill(Path(skyRect), with: .linearGradient(Gradient(stops: skyStops(s)), startPoint: .zero,
                                                      endPoint: CGPoint(x: 0, y: hy)))
        if s.dark || s.night { stars(&ctx, s) }

        // Halo : disque rose autour du soleil et lueur orangée étirée sur l'horizon.
        let center = s.sun
        var glow = ctx
        glow.blendMode = s.dark ? .plusLighter : .screen
        let haloR = d * (s.night ? 1.05 : 1.3)
        glow.fill(Path(ellipseIn: CGRect(x: center.x - haloR, y: center.y - haloR, width: 2 * haloR, height: 2 * haloR)),
                  with: .radialGradient(Gradient(colors: [Color(Synthwave.magenta).opacity(s.night ? 0.3 : 0.5),
                                                          Color(Synthwave.hotPink).opacity(0.16), .clear]),
                                        center: center, startRadius: d * 0.3, endRadius: haloR))
        var band = glow
        band.translateBy(x: center.x, y: hy)
        band.scaleBy(x: 1, y: 0.28)
        band.fill(Path(CGRect(x: -w * 1.2, y: -w * 1.2, width: w * 2.4, height: w * 2.4)),
                  with: .radialGradient(Gradient(colors: [Color(Synthwave.orange).opacity(s.night ? 0.25 : 0.45), .clear]),
                                        center: .zero, startRadius: 0, endRadius: max(w * 0.7, d)))

        sunDisc(&ctx, s)
        if !s.compact || w > 150 { ridge(&ctx, s) }
        if !s.compact { skyline(&ctx, s) }

        // Brume sur l'horizon.
        let hazeTop = hy - d * (s.compact ? 0.22 : 0.3)
        let haze = s.dark ? Color(Synthwave.hotPink) : c(0xFFD9C2)
        ctx.fill(Path(CGRect(x: 0, y: hazeTop, width: w, height: hy - hazeTop + 1)),
                 with: .linearGradient(Gradient(colors: [haze.opacity(0), haze.opacity(s.night ? 0.18 : 0.42)]),
                                       startPoint: CGPoint(x: 0, y: hazeTop), endPoint: CGPoint(x: 0, y: hy)))
    }

    /// Soleil rayé : dégradé jaune → orange → rose, bandes découpées de plus en plus larges.
    private static func sunDisc(_ ctx: inout GraphicsContext, _ s: NeonSceneSpec) {
        let d = s.sunDiameter, center = s.sun
        let rect = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        let stops: [Gradient.Stop] = s.night
            ? [.init(color: c(0xFF9A4A), location: 0), .init(color: c(0xE0306E), location: 0.5), .init(color: c(0x8A1A6A), location: 1)]
            : [.init(color: c(0xFFF3A6), location: 0), .init(color: Color(Synthwave.sun), location: 0.3),
               .init(color: Color(Synthwave.orange), location: 0.62), .init(color: Color(Synthwave.hotPink), location: 1)]
        ctx.drawLayer { layer in
            layer.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(stops: stops),
                                                                    startPoint: CGPoint(x: 0, y: rect.minY),
                                                                    endPoint: CGPoint(x: 0, y: rect.maxY)))
            layer.blendMode = .destinationOut
            let bands = s.compact ? 5 : 8
            for i in 0..<bands {
                let t = CGFloat(i) / CGFloat(bands)
                let y = center.y + d * (0.04 + t * 0.44)
                let bh = max(0.7, d * (0.008 + t * 0.042))
                layer.fill(Path(CGRect(x: rect.minX, y: y, width: d, height: bh)), with: .color(.black))
            }
        }
    }

    /// Collines lointaines, voilées par la brume.
    private static func ridge(_ ctx: inout GraphicsContext, _ s: NeonSceneSpec) {
        let w = s.size.width, hy = s.horizon, d = s.sunDiameter
        var rng = NeonRandom(seed: 7)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: hy + 1))
        let steps = 9
        var previous = CGPoint(x: 0, y: hy - d * 0.06)
        path.addLine(to: previous)
        for i in 1...steps {
            let x = w * CGFloat(i) / CGFloat(steps)
            let y = hy - d * CGFloat(0.04 + rng.next() * 0.12)
            path.addQuadCurve(to: CGPoint(x: x, y: y),
                              control: CGPoint(x: (previous.x + x) / 2, y: min(previous.y, y) - d * 0.05))
            previous = CGPoint(x: x, y: y)
        }
        path.addLine(to: CGPoint(x: w, y: hy + 1))
        path.closeSubpath()
        let tone: Color = s.dark ? c(0x3A1460, 0.92) : (s.night ? c(0x4A3285) : c(0xC98FC8, 0.9))
        ctx.fill(path, with: .color(tone))
    }

    /// Skyline art déco : tours à gradins, flèches, liserés néon et quelques fenêtres.
    private static func skyline(_ ctx: inout GraphicsContext, _ s: NeonSceneSpec) {
        let w = s.size.width, hy = s.horizon, d = s.sunDiameter
        let unit = max(0.6, min(1.4, d / 320))
        var rng = NeonRandom(seed: 1984)
        let body: [Color] = s.dark || s.night ? [c(0x2C1050), c(0x170830)] : [c(0x7A4DB4), c(0x4E2C88)]
        let windowColor = Color(Synthwave.sun).opacity(s.night ? 0.45 : 0.75)
        let free = d * 0.4

        func cluster(_ x0: CGFloat, _ x1: CGFloat) {
            guard x1 - x0 > 20 else { return }
            var x = x0
            var index = 0
            while x < x1 {
                let bw = CGFloat(16 + rng.next() * 22) * unit
                // Plus hautes au milieu du groupe.
                let mid = 1 - abs((x - x0) / max(1, x1 - x0) - 0.5) * 1.2
                let bh = CGFloat(24 + rng.next() * 60 + Double(mid) * 50) * unit
                building(&ctx, CGRect(x: x, y: hy - bh, width: bw, height: bh), index: index, rng: &rng,
                         body: body, window: windowColor, neon: index % 3 == 0 ? NeonPalette.cyan : NeonPalette.magenta,
                         unit: unit, night: s.night)
                x += bw + CGFloat(rng.next() * 6 - 2) * unit
                index += 1
            }
        }
        cluster(-4, s.sun.x - free)
        cluster(s.sun.x + free, w + 4)
    }

    private static func building(_ ctx: inout GraphicsContext, _ r: CGRect, index: Int, rng: inout NeonRandom,
                                 body: [Color], window: Color, neon: Color, unit: CGFloat, night: Bool) {
        var shape = Path(r)
        // Gradins (un ou deux) et parfois une flèche.
        let tiers = 1 + Int(rng.next() * 2)
        var top = r
        for _ in 0..<tiers {
            let tw = top.width * 0.62, th = max(4, r.height * 0.1)
            top = CGRect(x: top.midX - tw / 2, y: top.minY - th, width: tw, height: th)
            shape.addRect(top)
        }
        let spire = rng.next() < 0.35
        if spire {
            var p = Path()
            p.move(to: CGPoint(x: top.midX - 1.2 * unit, y: top.minY))
            p.addLine(to: CGPoint(x: top.midX, y: top.minY - r.height * 0.22))
            p.addLine(to: CGPoint(x: top.midX + 1.2 * unit, y: top.minY))
            p.closeSubpath()
            shape.addPath(p)
        }
        ctx.fill(shape, with: .linearGradient(Gradient(colors: body), startPoint: CGPoint(x: 0, y: top.minY),
                                              endPoint: CGPoint(x: 0, y: r.maxY)))
        // Liseré néon au sommet du corps.
        var trim = Path()
        trim.move(to: CGPoint(x: r.minX + 1, y: r.minY + 0.5))
        trim.addLine(to: CGPoint(x: r.maxX - 1, y: r.minY + 0.5))
        ctx.stroke(trim, with: .color(neon.opacity(night ? 0.35 : 0.8)), lineWidth: max(0.8, unit))
        // Fenêtres allumées, rares.
        let cols = max(1, Int(r.width / (5 * unit)))
        let rows = max(1, Int(r.height / (7 * unit)))
        let ww = 1.6 * unit, wh = 2.2 * unit
        for row in 0..<rows {
            for col in 0..<cols where rng.next() < 0.14 {
                let x = r.minX + 2.5 * unit + CGFloat(col) * (r.width - 5 * unit) / CGFloat(max(1, cols))
                let y = r.minY + 4 * unit + CGFloat(row) * 7 * unit
                guard y + wh < r.maxY - 2 else { continue }
                ctx.fill(Path(CGRect(x: x, y: y, width: ww, height: wh)), with: .color(window))
            }
        }
    }

    private static func stars(_ ctx: inout GraphicsContext, _ s: NeonSceneSpec) {
        let w = s.size.width, hy = s.horizon
        var rng = NeonRandom(seed: 42)
        let count = s.compact ? 18 : Int(min(140, w * hy / 5200))
        for _ in 0..<count {
            let x = CGFloat(rng.next()) * w
            let y = CGFloat(pow(rng.next(), 1.6)) * hy * 0.78
            let r = CGFloat(0.4 + rng.next() * 1.1)
            let a = 0.25 + rng.next() * 0.65
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(a)))
        }
    }

    // MARK: Sol

    /// Sol complet (vignette) : fond, lumières, oiseaux.
    static func drawFloor(_ context: GraphicsContext, _ s: NeonSceneSpec) {
        drawFloorBase(context, s)
        drawFloorLights(context, s)
        drawBirds(context, s)
    }

    /// Fond du sol (statique) : dégradé nocturne.
    static func drawFloorBase(_ ctx: GraphicsContext, _ s: NeonSceneSpec) {
        let w = s.size.width, h = s.size.height, hy = s.horizon
        guard w > 0, h > hy else { return }
        ctx.fill(Path(CGRect(x: 0, y: hy, width: w, height: h - hy)),
                 with: .linearGradient(Gradient(colors: floorColors(s)), startPoint: CGPoint(x: 0, y: hy),
                                       endPoint: CGPoint(x: 0, y: h)))
    }

    /// Bande animée qui contient le sol et la lueur de l'horizon (seule zone redessinée).
    static func floorBand(_ s: NeonSceneSpec) -> CGRect {
        let top = max(0, s.horizon - 6)
        return CGRect(x: 0, y: top, width: s.size.width, height: max(0, s.size.height - top))
    }

    /// Lumières du sol : reflet du soleil sur l'eau, grille en perspective (fuyantes, et
    /// transversales si `rows`, sinon animées à part), ligne d'horizon néon.
    static func drawFloorLights(_ context: GraphicsContext, _ s: NeonSceneSpec, rows drawsRows: Bool = true,
                                flicker: Double = 1) {
        let w = s.size.width, h = s.size.height, hy = s.horizon, d = s.sunDiameter
        guard w > 0, h > hy else { return }
        var ctx = context
        let floor = CGRect(x: 0, y: hy, width: w, height: h - hy)
        var g = ctx
        g.clip(to: Path(floor))
        g.blendMode = .plusLighter

        // Reflet : colonne lumineuse et traits qui ondulent.
        var column = g
        column.translateBy(x: s.sun.x, y: hy)
        column.scaleBy(x: 1, y: 1.8)
        column.fill(Path(CGRect(x: -d, y: -d, width: 2 * d, height: 2 * d)),
                    with: .radialGradient(Gradient(colors: [Color(Synthwave.magenta).opacity(s.night ? 0.12 : 0.3), .clear]),
                                          center: .zero, startRadius: 0, endRadius: d * 0.4))
        // Bande courte sous l'horizon : le reflet ne passe pas derrière les textes.
        let rows = s.compact ? 6 : 9
        let depth = min((h - hy) * 0.3, d * 0.2)
        for i in 0..<rows {
            let f = Double(i) / Double(rows)
            let y = hy + 2 + depth * CGFloat(pow(f, 1.2))
            let thick = max(0.7, CGFloat(0.8 + f * (s.compact ? 1.2 : 2.2)))
            // Traits irréguliers, légèrement décalés : l'eau ondule.
            let wobble = 0.78 + 0.22 * sin(Double(i) * 1.9 + 0.6)
            let rw = d * 0.6 * CGFloat((1 - 0.55 * f) * wobble)
            let dx = CGFloat(sin(Double(i) * 2.3)) * d * 0.025
            let tone = Color(mix(Synthwave.sun, Synthwave.hotPink, f * 1.4))
            g.fill(Path(roundedRect: CGRect(x: s.sun.x - rw / 2 + dx, y: y, width: rw, height: thick), cornerRadius: thick / 2),
                   with: .color(tone.opacity((s.night ? 0.3 : 0.85) * (1 - f * 0.7))))
        }

        grid(&ctx, s, rows: drawsRows)

        // Ligne d'horizon (vacille très légèrement).
        let level = s.night ? 0.55 : flicker
        let sx = Double(min(0.9, max(0.1, s.sun.x / w)))
        let line = Gradient(stops: [
            .init(color: NeonPalette.cyan.opacity(0.7), location: 0),
            .init(color: NeonPalette.magenta, location: sx - 0.1),
            .init(color: c(0xFFF0F8), location: sx),
            .init(color: NeonPalette.magenta, location: sx + 0.1),
            .init(color: NeonPalette.cyan.opacity(0.7), location: 1),
        ])
        var horizon = ctx
        horizon.opacity = level
        horizon.blendMode = .plusLighter
        horizon.fill(Path(CGRect(x: 0, y: hy - 5, width: w, height: 10)),
                     with: .linearGradient(Gradient(colors: [.clear, NeonPalette.magenta.opacity(0.45), .clear]),
                                           startPoint: CGPoint(x: 0, y: hy - 5), endPoint: CGPoint(x: 0, y: hy + 5)))
        horizon.fill(Path(CGRect(x: 0, y: hy - 0.75, width: w, height: 1.5)),
                     with: .linearGradient(line, startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
    }

    /// Vitesse de défilement de la grille (lignes par seconde).
    static let gridSpeed = 0.32

    static func gridRowCount(_ s: NeonSceneSpec) -> Int { s.compact ? 12 : 26 }

    static func gridColor(_ s: NeonSceneSpec) -> Color {
        if s.night { return c(0x8A4DFF, 0.6) }
        return s.dark ? Color(Synthwave.magenta) : c(0xFF79CF)
    }

    /// Ordonnée d'une transversale à la profondeur `z` (1 = bas de l'image, ∞ = horizon).
    static func gridRowY(_ s: NeonSceneSpec, depthIndex z: Double) -> CGFloat {
        guard z > 0.02 else { return s.size.height * 4 }
        return s.horizon + (s.size.height - s.horizon) * CGFloat(1 / z)
    }

    /// Opacité de la grille selon la hauteur : nulle à l'horizon, pleine en bas.
    static func gridAlpha(_ s: NeonSceneSpec, y: CGFloat) -> Double {
        let depth = s.size.height - s.horizon
        guard depth > 0 else { return 0 }
        let f = Double(min(1, max(0, (y - s.horizon) / depth)))
        return f < 0.25 ? f / 0.25 * 0.55 : 0.55 + (f - 0.25) / 0.75 * 0.45
    }

    /// Grille en perspective : fuyantes vers le soleil et, si `rows`, transversales figées
    /// (sinon animées par `NeonGridRows`).
    private static func grid(_ ctx: inout GraphicsContext, _ s: NeonSceneSpec, rows: Bool) {
        let w = s.size.width, h = s.size.height, hy = s.horizon
        let depth = h - hy
        guard depth > 4 else { return }
        let color = gridColor(s)
        let vx = s.sun.x
        var path = Path()
        // Fuyantes : espacement au bas de l'image, convergence à l'horizon.
        let spacing = max(s.compact ? 22 : 34, w / (s.compact ? 9 : 15))
        let reach = Int((max(vx, w - vx) / spacing).rounded(.up)) + 3
        for i in -reach...reach {
            let xb = vx + CGFloat(i) * spacing * 2.2
            let xt = vx + CGFloat(i) * spacing * 0.09
            path.move(to: CGPoint(x: xt, y: hy))
            path.addLine(to: CGPoint(x: xb, y: h + spacing))
        }
        if rows {
            for k in 0..<gridRowCount(s) {
                let y = gridRowY(s, depthIndex: Double(k) + 0.6)
                guard y <= h + 2 else { continue }
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
            }
        }
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(0.55), location: 0.25),
                             .init(color: color, location: 1)]),
            startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: h))
        var halo = ctx
        halo.opacity = 0.35
        halo.stroke(path, with: shading, lineWidth: s.compact ? 2 : 4)
        ctx.stroke(path, with: shading, lineWidth: s.compact ? 0.7 : 1.1)
    }

    /// Deux oiseaux qui planent près du soleil (pas la nuit ni en petit).
    static func drawBirds(_ ctx: GraphicsContext, _ s: NeonSceneSpec) {
        guard !s.night && !s.compact else { return }
        let t = 0.0
        let d = s.sunDiameter
        let ink = s.dark ? c(0x12061F) : c(0x3A1E66)
        let drift = CGFloat(sin(t * 0.07)) * d * 0.12
        let birds: [(CGPoint, CGFloat, Double)] = [
            (CGPoint(x: s.sun.x + d * 0.62 + drift, y: s.sun.y - d * 0.5), d * 0.045, 0),
            (CGPoint(x: s.sun.x + d * 0.8 + drift * 0.7, y: s.sun.y - d * 0.38), d * 0.032, 1.7),
        ]
        for (p, span, phase) in birds {
            let flap = CGFloat(sin(t * 2.6 + phase)) * span * 0.35
            var wing = Path()
            wing.move(to: CGPoint(x: p.x - span, y: p.y - span * 0.2 - flap))
            wing.addQuadCurve(to: p, control: CGPoint(x: p.x - span * 0.45, y: p.y - span * 0.55))
            wing.addQuadCurve(to: CGPoint(x: p.x + span, y: p.y - span * 0.2 - flap),
                              control: CGPoint(x: p.x + span * 0.45, y: p.y - span * 0.55))
            ctx.stroke(wing, with: .color(ink), style: StrokeStyle(lineWidth: max(1, span * 0.16), lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Premier plan

    /// Palmiers en silhouette, liserés de rose côté soleil ; vignettage la nuit.
    static func drawPalms(_ context: GraphicsContext, _ s: NeonSceneSpec) {
        let w = s.size.width, h = s.size.height
        guard w > 0, h > 0 else { return }
        var ctx = context
        let ink = s.dark || s.night ? c(0x0A0418) : c(0x3A1E66)
        let rim = Color(Synthwave.hotPink).opacity(s.night ? 0.35 : 0.75)
        if s.compact {
            guard w > 60 else { return }
            palm(&ctx, base: CGPoint(x: w * 0.05, y: h + 2), height: h * 0.74, lean: 1, ink: ink, rim: rim)
            palm(&ctx, base: CGPoint(x: w * 0.96, y: h + 2), height: h * 0.56, lean: -1, ink: ink, rim: rim)
        } else if s.foregroundPalms {
            let unit = min(h, w * 0.95)
            palm(&ctx, base: CGPoint(x: w * 0.025, y: h + 8), height: unit * 0.6, lean: 0.8, ink: ink, rim: rim)
            palm(&ctx, base: CGPoint(x: w * 0.1, y: h + 8), height: unit * 0.42, lean: 0.65, ink: ink, rim: rim)
            palm(&ctx, base: CGPoint(x: w * 0.975, y: h + 8), height: unit * 0.55, lean: -1, ink: ink, rim: rim)
        } else {
            let hy = s.horizon, d = s.sunDiameter
            palm(&ctx, base: CGPoint(x: w * 0.01, y: hy + (h - hy) * 0.15), height: d * 0.62, lean: 0.5, ink: ink, rim: rim)
            palm(&ctx, base: CGPoint(x: w * 0.99, y: hy + (h - hy) * 0.1), height: d * 0.62, lean: -1, ink: ink, rim: rim)
        }
        if s.dark && !s.compact {
            let center = CGPoint(x: w / 2, y: h * 0.45)
            let r = hypot(w, h) * 0.62
            ctx.fill(Path(CGRect(origin: .zero, size: s.size)),
                     with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.32)]), center: center,
                                           startRadius: r * 0.55, endRadius: r))
        }
    }

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * b.x + t * t * c.x, y: u * u * a.y + 2 * u * t * b.y + t * t * c.y)
    }

    /// Normale unitaire de la courbe de Bézier quadratique en `t`.
    private static func normal(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: CGFloat) -> CGPoint {
        let dx = 2 * (1 - t) * (b.x - a.x) + 2 * t * (c.x - b.x)
        let dy = 2 * (1 - t) * (b.y - a.y) + 2 * t * (c.y - b.y)
        let len = max(0.0001, hypot(dx, dy))
        return CGPoint(x: -dy / len, y: dx / len)
    }

    /// Palmier : tronc courbe effilé et annelé, palmes dentelées, noix de coco.
    private static func palm(_ ctx: inout GraphicsContext, base: CGPoint, height: CGFloat, lean: CGFloat,
                             ink: Color, rim: Color) {
        let top = CGPoint(x: base.x + lean * height * 0.3, y: base.y - height)
        let control = CGPoint(x: base.x + lean * height * 0.02, y: base.y - height * 0.55)
        let n = 22
        var sideA: [CGPoint] = [], sideB: [CGPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let p = quad(base, control, top, t)
            let nn = normal(base, control, top, t)
            let half = height * (0.045 * (1 - t) + 0.02 * t)
            sideA.append(CGPoint(x: p.x + nn.x * half, y: p.y + nn.y * half))
            sideB.append(CGPoint(x: p.x - nn.x * half, y: p.y - nn.y * half))
        }
        var trunk = Path()
        trunk.addLines(sideA + sideB.reversed())
        trunk.closeSubpath()
        ctx.fill(trunk, with: .color(ink))
        // Liseré côté soleil (vers le centre de l'image) et anneaux du tronc.
        let sunward = (sideA[n / 2].x > sideB[n / 2].x) == (lean > 0) ? sideA : sideB
        var edge = Path()
        edge.addLines(Array(sunward.dropFirst(2)))
        ctx.stroke(edge, with: .color(rim.opacity(0.7)), lineWidth: max(0.6, height * 0.004))
        var rings = Path()
        for i in stride(from: 2, to: n, by: 2) {
            rings.move(to: sideA[i])
            rings.addLine(to: sideB[i])
        }
        ctx.stroke(rings, with: .color(rim.opacity(0.18)), lineWidth: max(0.5, height * 0.003))

        // Palmes : angle (0° = vers l'extérieur, -90° = vers le haut) et longueur relative.
        let fronds: [(Double, CGFloat)] = [(-174, 0.5), (-150, 0.56), (-122, 0.44), (-92, 0.34),
                                           (-62, 0.46), (-34, 0.58), (-8, 0.56), (16, 0.44)]
        let direction: CGFloat = lean >= 0 ? 1 : -1
        for (degrees, relative) in fronds {
            let a = degrees * .pi / 180
            let length = height * relative
            let dx = CGFloat(cos(a)) * direction, dy = CGFloat(sin(a))
            let droop = length * 0.45 * (1 - abs(dy))
            let end = CGPoint(x: top.x + dx * length, y: top.y + dy * length * 0.55 + droop)
            let ctrl = CGPoint(x: top.x + dx * length * 0.55, y: top.y + dy * length * 0.6 - length * 0.2)
            leaf(&ctx, from: top, control: ctrl, to: end, width: length * 0.11, ink: ink, rim: rim)
        }
        let nut = height * 0.022
        for (ox, oy) in [(-0.9, 0.6), (0.7, 0.9), (0.0, 1.5)] as [(CGFloat, CGFloat)] {
            let p = CGPoint(x: top.x + ox * nut * 1.6, y: top.y + oy * nut * 1.4)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - nut, y: p.y - nut, width: 2 * nut, height: 2 * nut)), with: .color(ink))
        }
    }

    /// Palme : nervure courbe, folioles en dents de scie, liseré lumineux sur le dessus.
    private static func leaf(_ ctx: inout GraphicsContext, from a: CGPoint, control b: CGPoint, to c: CGPoint,
                             width: CGFloat, ink: Color, rim: Color) {
        let n = 26
        var upper: [CGPoint] = [], lower: [CGPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let p = quad(a, b, c, t)
            let nn = normal(a, b, c, t)
            let taper = CGFloat(pow(Double(sin(.pi * min(1, t * 1.1))), 0.8))
            // Folioles : dents régulières, plus marquées vers la pointe.
            let tooth: CGFloat = (i > 1 && i % 2 == 1) ? 0.55 + 0.25 * (1 - t) : 1
            let wu = width * taper * (0.55 + 0.45 * tooth) * 0.7, wl = width * taper * tooth
            upper.append(CGPoint(x: p.x + nn.x * wu, y: p.y + nn.y * wu))
            lower.append(CGPoint(x: p.x - nn.x * wl, y: p.y - nn.y * wl))
        }
        var shape = Path()
        shape.addLines(upper + lower.reversed())
        shape.closeSubpath()
        ctx.fill(shape, with: .color(ink))
        // Liseré sur le côté le plus haut (éclairé par le ciel).
        let lit = upper[n / 2].y < lower[n / 2].y ? upper : lower
        var edge = Path()
        edge.addLines(lit)
        ctx.stroke(edge, with: .color(rim), lineWidth: max(0.5, width * 0.08))
    }
}

/// Générateur pseudo-aléatoire déterministe (même scène à chaque dessin).
struct NeonRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - Explorateur

/// Fond de l'explorateur : nuit indigo (ou pastel doré), lueur et grille discrètes en bas.
struct NeonExplorerBackground: View {
    var dark: Bool

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let colors: [Color] = dark ? [Color(hex: 0x0A0520), Color(hex: 0x1B0F3A), Color(hex: 0x2B1055)]
                                       : [Color(hex: 0xFFF3EC), Color(hex: 0xFCE4F0), Color(hex: 0xEEDDFB)]
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let hy = h * 0.8
            var glow = ctx
            glow.translateBy(x: w / 2, y: hy)
            glow.scaleBy(x: 1, y: 0.35)
            glow.fill(Path(CGRect(x: -w, y: -w, width: 2 * w, height: 2 * w)),
                      with: .radialGradient(Gradient(colors: [Color(Synthwave.magenta).opacity(dark ? 0.32 : 0.16), .clear]),
                                            center: .zero, startRadius: 0, endRadius: w * 0.6))
            let tone = dark ? Color(Synthwave.magenta) : Color(hex: 0xD66BB8)
            var grid = Path()
            for i in -12...12 {
                grid.move(to: CGPoint(x: w / 2 + CGFloat(i) * w * 0.012, y: hy))
                grid.addLine(to: CGPoint(x: w / 2 + CGFloat(i) * w * 0.16, y: h + 40))
            }
            for k in 1...9 {
                let y = hy + (h - hy) * CGFloat(1.0 / Double(10 - k)) * 0.98
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: w, y: y))
            }
            ctx.stroke(grid, with: .linearGradient(Gradient(colors: [tone.opacity(0), tone.opacity(dark ? 0.4 : 0.3)]),
                                                   startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: h)),
                       lineWidth: 1)
            ctx.fill(Path(CGRect(x: 0, y: hy - 0.5, width: w, height: 1)),
                     with: .linearGradient(Gradient(colors: [NeonPalette.cyan.opacity(0), tone.opacity(0.7), NeonPalette.cyan.opacity(0)]),
                                           startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: w, y: hy)))
        }
        .accessibilityHidden(true)
    }
}
