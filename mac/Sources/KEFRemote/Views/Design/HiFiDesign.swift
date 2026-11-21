import KEFKit
import SwiftUI

// Design « Hi-Fi analogique » : façade d'ampli haut de gamme, toujours sombre.

enum HiFiPalette {
    static let background = Color(hex: 0x1B1B1D)
    static let panel = Color(hex: 0x232326)
    static let display = Color(hex: 0x0D0D0E)
    static let edge = Color(hex: 0x3A3A3E)
    static let amber = Color(hex: 0xE8A03A)
    static let amberDim = Color(hex: 0xE8A03A, opacity: 0.18)
    static let text = Color(hex: 0xDAD4CA)
    static let secondary = Color(hex: 0x948E85)
    static let tertiary = Color(hex: 0x5E5A55)
    static let keyTop = Color(hex: 0x323235)
    static let keyBottom = Color(hex: 0x252528)
}

/// Libellé de façade : monospace, capitales espacées.
private struct PanelLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = HiFiPalette.secondary

    var body: some View {
        Text(text.interfaceUppercased)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(size * 0.22)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Aluminium brossé : fond anthracite et fines stries horizontales.
struct BrushedMetal: View {
    var body: some View {
        HiFiPalette.background
            .overlay {
                Canvas { ctx, size in
                    var seed: UInt64 = 0x9E37_79B9
                    var y: CGFloat = 0
                    while y < size.height {
                        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        let r = Double(seed >> 40) / Double(1 << 24)
                        let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                        ctx.fill(Path(rect), with: .color(.white.opacity(0.012 + r * 0.03)))
                        y += 1 + CGFloat(r * 2.5)
                    }
                }
            }
            .overlay {
                LinearGradient(colors: [.white.opacity(0.05), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
    }
}

/// Touche rectangulaire façon platine ; `active` = bordée d'ambre.
struct HiFiKeyStyle: ButtonStyle {
    var active = false
    var cornerRadius: CGFloat = 3
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(active ? HiFiPalette.amber : HiFiPalette.text)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: pressed ? [HiFiPalette.keyBottom, HiFiPalette.keyTop]
                                                         : [HiFiPalette.keyTop, HiFiPalette.keyBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle().fill(.white.opacity(pressed ? 0.02 : 0.08)).frame(height: 1).padding(.horizontal, 1)
                    }
                    .shadow(color: .black.opacity(0.6), radius: pressed ? 0.5 : 1.5, y: pressed ? 0.5 : 1.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(active ? HiFiPalette.amber : .black.opacity(0.7), lineWidth: active ? 1.5 : 1)
            }
            .shadow(color: active ? HiFiPalette.amber.opacity(0.35) : .clear, radius: 4)
            .offset(y: pressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// Voyant (état de connexion, lecture).
private struct PanelLED: View {
    var on: Bool
    var color: Color = HiFiPalette.amber

    var body: some View {
        Circle()
            .fill(on ? color : HiFiPalette.tertiary.opacity(0.6))
            .frame(width: 6, height: 6)
            .shadow(color: on ? color.opacity(0.9) : .clear, radius: 3)
    }
}

private func ledColor(_ status: ConnectionStatus) -> Color {
    switch status {
    case .online: Color(hex: 0x7BD88F)
    case .connecting: HiFiPalette.amber
    case .offline: Color(hex: 0xE5533D)
    case .notConfigured: HiFiPalette.tertiary
    }
}

// MARK: - Molette de volume

/// Grande molette rotative : glisser en tournant par le bord ou verticalement depuis le
/// centre, molette de la souris / trackpad, flèches du clavier ; graduations allumées
/// jusqu'à la valeur, index ambre, valeur au centre. Réglable avec VoiceOver.
struct VolumeKnob: View {
    let store: SpeakerStore
    var diameter: CGFloat = 210
    var showsScale = true

    @State private var dragValue: Double?
    @State private var lastLocation: CGPoint?
    @State private var rotating = false
    @State private var scroll = ScrollAccumulator()
    @FocusState private var focused: Bool

    var body: some View {
        let snap = store.snapshot
        let enabled = store.status.isOnline && snap.isOn
        let value = Double(snap.volume)
        let angle = KnobGeometry.angle(forValue: value)
        let knob = diameter * (showsScale ? 0.68 : 0.8)

        ZStack {
            if showsScale {
                scale(value: enabled ? value : -1)
            }
            // Corps de la molette.
            Circle()
                .fill(AngularGradient(colors: [Color(hex: 0x4C4C50), Color(hex: 0x2A2A2D), Color(hex: 0x56565A),
                                               Color(hex: 0x2A2A2D), Color(hex: 0x4C4C50)], center: .center))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.10), .clear], center: UnitPoint(x: 0.35, y: 0.25),
                                                      startRadius: 0, endRadius: knob * 0.7)))
                .overlay(Circle().strokeBorder(.black.opacity(0.8), lineWidth: 1.5))
                .overlay(Circle().inset(by: knob * 0.09).strokeBorder(.black.opacity(0.35), lineWidth: 1))
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.7), radius: diameter * 0.05, y: diameter * 0.03)
            // Index ambre.
            Capsule()
                .fill(enabled ? HiFiPalette.amber : HiFiPalette.tertiary)
                .frame(width: max(2.5, diameter * 0.016), height: knob * 0.16)
                .shadow(color: enabled ? HiFiPalette.amber.opacity(0.8) : .clear, radius: 3)
                .offset(y: -knob * 0.36)
                .rotationEffect(.degrees(angle))
                .animation(.interactiveSpring(duration: 0.18), value: angle)
            // Valeur au centre.
            VStack(spacing: 0) {
                Text(verbatim: snap.isMuted && enabled ? "MUTE" : (enabled ? "\(snap.volume)" : "--"))
                    .font(.system(size: knob * (snap.isMuted && enabled ? 0.15 : 0.24), weight: .medium, design: .monospaced))
                    .foregroundStyle(enabled ? HiFiPalette.amber : HiFiPalette.tertiary)
                    .contentTransition(.numericText(value: value))
                    .shadow(color: enabled ? HiFiPalette.amber.opacity(0.45) : .clear, radius: 4)
                if showsScale {
                    PanelLabel(text: "Volume", size: max(7, knob * 0.055), color: HiFiPalette.secondary)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .overlay {
            if focused {
                Circle().strokeBorder(HiFiPalette.amber.opacity(0.5), lineWidth: 1.5)
                    .frame(width: knob + 8, height: knob + 8)
            }
        }
        .gesture(dragGesture(enabled: enabled))
        .background(ScrollWheelReader { delta, precise in
            guard enabled else { return }
            let steps = scroll.steps(for: delta, precise: precise)
            if steps != 0 { store.adjustVolume(by: steps) }
        })
        .focusable(enabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            guard enabled else { return .ignored }
            store.adjustVolume(by: press.key == .upArrow || press.key == .rightArrow ? 2 : -2)
            return .handled
        }
        .help("Volume : tournez par le bord, glissez verticalement, molette ou flèches")
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(snap.isMuted ? Text("Son coupé") : Text(Double(snap.volume) / 100, format: .percent))
        .accessibilityHint("Molette rotative. Balayez vers le haut ou le bas pour régler.")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: store.adjustVolume(by: 2)
            case .decrement: store.adjustVolume(by: -2)
            @unknown default: break
            }
        }
    }

    /// Graduations (41 traits, majeurs tous les 10) allumées jusqu'à la valeur.
    private func scale(value: Double) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = size.width / 2 - 1
            for i in 0...40 {
                let v = Double(i) * 2.5
                let major = i % 4 == 0
                let a = KnobGeometry.angle(forValue: v) * .pi / 180
                let inner = outer - (major ? size.width * 0.07 : size.width * 0.04)
                var p = Path()
                p.move(to: CGPoint(x: c.x + sin(a) * inner, y: c.y - cos(a) * inner))
                p.addLine(to: CGPoint(x: c.x + sin(a) * outer, y: c.y - cos(a) * outer))
                let lit = v <= value
                ctx.stroke(p, with: .color(lit ? HiFiPalette.amber : HiFiPalette.tertiary),
                           lineWidth: major ? 2 : 1)
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                PanelLabel(text: "Min", size: 8, color: HiFiPalette.tertiary)
                Spacer()
                PanelLabel(text: "Max", size: 8, color: HiFiPalette.tertiary)
            }
            .padding(.horizontal, diameter * 0.17)
            .padding(.bottom, diameter * 0.02)
        }
        .allowsHitTesting(false)
    }

    private func dragGesture(enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard enabled else { return }
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                if dragValue == nil {
                    dragValue = Double(store.snapshot.volume)
                    lastLocation = g.startLocation
                    // Par le bord : rotation ; depuis le centre : glissement vertical.
                    rotating = hypot(g.startLocation.x - center.x, g.startLocation.y - center.y) > diameter * 0.2
                }
                guard var v = dragValue, let last = lastLocation else { return }
                if rotating, hypot(g.location.x - center.x, g.location.y - center.y) > diameter * 0.08 {
                    let d = KnobGeometry.delta(from: KnobGeometry.angle(of: last, around: center),
                                               to: KnobGeometry.angle(of: g.location, around: center))
                    v += KnobGeometry.valueDelta(forRotation: d)
                } else if !rotating {
                    v -= Double(g.location.y - last.y) * 0.5
                }
                v = min(max(v, 0), 100)
                dragValue = v
                lastLocation = g.location
                let rounded = Int(v.rounded())
                if rounded != store.snapshot.volume { store.setVolume(rounded) }
            }
            .onEnded { _ in
                dragValue = nil
                lastLocation = nil
            }
    }
}

// MARK: - Vumètre

/// Vumètre décoratif (deux canaux), animé pendant la lecture, figé sinon.
struct VUMeter: View {
    var active: Bool
    var level: Double = 0.6
    var segments = 18
    var height: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 3) {
                channel("L", value: active ? signal(t, phase: 0) : 0)
                channel("R", value: active ? signal(t, phase: 1.7) : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func signal(_ t: Double, phase: Double) -> Double {
        let s = (sin(t * 7.3 + phase) + sin(t * 3.1 + phase * 2) * 0.6 + sin(t * 13.7 + phase) * 0.3) / 1.9
        return min(1, max(0.08, (0.55 + 0.45 * s) * (0.35 + 0.75 * level)))
    }

    private func channel(_ name: String, value: Double) -> some View {
        HStack(spacing: 5) {
            Text(name).font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundStyle(HiFiPalette.tertiary)
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { i in
                    let lit = Double(i) < value * Double(segments)
                    let hot = i >= segments - 3
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(lit ? (hot ? Color(hex: 0xF0643A) : HiFiPalette.amber) : HiFiPalette.amberDim)
                        .frame(height: height)
                        .shadow(color: lit ? HiFiPalette.amber.opacity(0.5) : .clear, radius: 2)
                }
            }
        }
    }
}

// MARK: - Éléments de façade

/// Afficheur : état, titre, artiste, progression, vumètre.
private struct HiFiDisplay: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        HStack(alignment: .center, spacing: compact ? 10 : 16) {
            CoverArtwork(snapshot: snap, cornerRadius: 2)
                .frame(width: compact ? 54 : 112, height: compact ? 54 : 112)
                .saturation(0.85)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.black.opacity(0.8), lineWidth: 1))
            VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                HStack(spacing: 6) {
                    PanelLED(on: snap.isPlaying)
                    PanelLabel(text: NowPlayingText.kicker(model), size: compact ? 8 : 9, color: HiFiPalette.amber.opacity(0.8))
                }
                Text((compact ? NowPlayingText.compactTitle(model) : NowPlayingText.title(model)).interfaceUppercased)
                    .font(.system(size: compact ? 13 : 20, weight: .semibold, design: .monospaced))
                    .tracking(compact ? 0.5 : 1)
                    .foregroundStyle(HiFiPalette.amber)
                    .shadow(color: HiFiPalette.amber.opacity(0.35), radius: 4)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                Text(compact ? NowPlayingText.compactSubtitle(model) : NowPlayingText.subtitle(model))
                    .font(.system(size: compact ? 10 : 12, design: .monospaced))
                    .foregroundStyle(HiFiPalette.text.opacity(0.75))
                    .lineLimit(compact ? 1 : 2)
                if !compact {
                    Spacer(minLength: 2)
                    if let duration = snap.player.durationMs, !snap.player.isLive, snap.isOn {
                        HiFiProgress(store: store, duration: duration)
                    }
                }
                VUMeter(active: snap.isPlaying, level: Double(snap.volume) / 100, segments: compact ? 22 : 24,
                        height: compact ? 3 : 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: snap.player.title)
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(HiFiPalette.display)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.black, lineWidth: 1))
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom).frame(height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .shadow(color: .white.opacity(0.06), radius: 0, y: 1)
        }
    }
}

/// Progression façon afficheur (pistes à durée connue uniquement).
private struct HiFiProgress: View {
    let store: SpeakerStore
    let duration: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = store.estimatedPosition(at: context.date) ?? 0
            let fraction = duration > 0 ? min(1, Double(position) / Double(duration)) : 0
            HStack(spacing: 8) {
                Text(formatTime(position))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(HiFiPalette.amberDim)
                        Rectangle().fill(HiFiPalette.amber).frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 2)
                Text("-" + formatTime(max(0, duration - position)))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(HiFiPalette.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Progression")
        .accessibilityValue("\(formatTime(store.estimatedPosition())) sur \(formatTime(duration))")
    }
}

/// Touches de transport (sur une radio, précédent / suivant zappent entre les favoris).
private struct HiFiTransport: View {
    @Environment(AppModel.self) private var model
    var keyWidth: CGFloat = 54
    var keyHeight: CGFloat = 30

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let canControl = store.status.isOnline && snap.isOn
        let previous = model.skipPlan(.previous), next = model.skipPlan(.next)
        HStack(spacing: 8) {
            key("backward.end.fill", label: previous.label, help: previous.help) {
                model.skip(.previous)
            }
            .disabled(!previous.isEnabled)
            key(snap.isPlaying ? (snap.player.isLive ? "stop.fill" : "pause.fill") : "play.fill",
                label: PlayPauseText.label(snap), help: PlayPauseText.help(snap), wide: true, active: snap.isPlaying) {
                Task { await store.playPause() }
            }
            .disabled(!canControl)
            key("forward.end.fill", label: next.label, help: next.help) {
                model.skip(.next)
            }
            .disabled(!next.isEnabled)
        }
    }

    private func key(_ symbol: String, label: String, help: String, wide: Bool = false, active: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: keyHeight * 0.38, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: wide ? keyWidth * 1.4 : keyWidth, height: keyHeight)
        }
        .buttonStyle(HiFiKeyStyle(active: active))
        .help(help)
        .accessibilityLabel(label)
    }
}

/// Touches de source (WIFI, BT, TV, OPT, COAX, AUX).
private struct HiFiSourceKeys: View {
    let store: SpeakerStore
    var height: CGFloat = 30
    var fontSize: CGFloat = 10

    var body: some View {
        let snap = store.snapshot
        HStack(spacing: 6) {
            ForEach(snap.sources) { source in
                let selected = snap.isOn && snap.source == source
                Button { Task { await store.selectSource(source) } } label: {
                    VStack(spacing: 3) {
                        PanelLED(on: selected)
                            .scaleEffect(0.8)
                        Text(source.panelLabel)
                            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                            .tracking(fontSize * 0.15)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                }
                .buttonStyle(HiFiKeyStyle(active: selected))
                .help(source.label)
                .accessibilityLabel("Source \(source.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .disabled(!store.status.isOnline)
        .animation(.easeOut(duration: 0.2), value: snap.source)
        .animation(.easeOut(duration: 0.2), value: snap.power)
    }
}

/// Bouton marche / veille rond, cerclé d'ambre quand l'enceinte est allumée.
private struct HiFiPowerButton: View {
    let store: SpeakerStore
    var size: CGFloat = 34

    var body: some View {
        let on = store.snapshot.isOn
        Button { Task { await store.togglePower() } } label: {
            Image(systemName: "power")
                .font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size)
                .foregroundStyle(on ? HiFiPalette.amber : HiFiPalette.secondary)
                .background(Circle().fill(LinearGradient(colors: [HiFiPalette.keyTop, HiFiPalette.keyBottom],
                                                         startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(on ? HiFiPalette.amber : .black.opacity(0.7), lineWidth: on ? 1.5 : 1))
                .shadow(color: on ? HiFiPalette.amber.opacity(0.4) : .black.opacity(0.5), radius: on ? 5 : 1.5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!store.status.isOnline)
        .help(on ? "Mettre en veille" : "Allumer")
        .accessibilityLabel(on ? "Mettre en veille" : "Allumer")
    }
}

/// Touche « MUTE ».
private struct HiFiMuteKey: View {
    let store: SpeakerStore
    var width: CGFloat = 72

    var body: some View {
        let snap = store.snapshot
        Button { store.toggleMute() } label: {
            HStack(spacing: 5) {
                PanelLED(on: snap.isMuted && snap.isOn)
                Text(verbatim: "MUTE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
            }
            .frame(width: width, height: 26)
        }
        .buttonStyle(HiFiKeyStyle(active: snap.isMuted && snap.isOn))
        .disabled(!(store.status.isOnline && snap.isOn))
        .help(snap.isMuted ? "Rétablir le son (⌥⌘↓)" : "Couper le son (⌥⌘↓)")
        .accessibilityLabel(snap.isMuted ? "Rétablir le son" : "Couper le son")
    }
}

/// Préréglages : touches numérotées « 1 RADIO CUIVRE ».
private struct HiFiPresets: View {
    @Environment(AppModel.self) private var model
    var limit: Int?
    var columns: [GridItem] = [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 8)]
    var compact = false
    @State private var dropTarget: String?

    var body: some View {
        let items = Array(model.favorites.items.enumerated()).prefix(limit ?? .max)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.element.id) { index, station in
                let current = model.isCurrent(station)
                HStack(spacing: compact ? 5 : 8) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: compact ? 11 : 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(HiFiPalette.amber)
                        .frame(minWidth: compact ? 12 : 18)
                    Text(station.title.interfaceUppercased)
                        .font(.system(size: compact ? 9 : 11, weight: .medium, design: .monospaced))
                        .tracking(compact ? 0.3 : 0.8)
                        .foregroundStyle(current ? HiFiPalette.amber : HiFiPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if model.store.loadingStationID == station.id {
                        ProgressView().controlSize(.mini)
                    } else if current {
                        PanelLED(on: model.store.snapshot.isPlaying)
                    }
                }
                .padding(.horizontal, compact ? 7 : 10)
                .frame(height: compact ? 26 : 34)
                .background {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient(colors: [HiFiPalette.keyTop, HiFiPalette.keyBottom], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1.5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(current ? HiFiPalette.amber : .black.opacity(0.7), lineWidth: current ? 1.5 : 1)
                }
                .overlay {
                    if dropTarget == station.id {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(HiFiPalette.amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .padding(-3)
                    }
                }
                .contentShape(Rectangle())
                .favoriteInteractions(station: station, index: index, dropTarget: $dropTarget)
                .help(station.description ?? station.title)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StationAccessibility.label(String(localized: "Préréglage \(index + 1), \(station.title)"), current: current))
                .accessibilityAddTraits(.isButton)
            }
        }
        .animation(.spring(duration: 0.3), value: model.favorites.items)
    }
}

// MARK: - Fenêtre principale

struct HiFiMainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        let store = model.store
        GeometryReader { geo in
            // Molette et afficheur à l'échelle de la fenêtre (les préréglages défilent dessous).
            let knob = max(130, min(196, geo.size.height * 0.34, (geo.size.width - 52) * 0.3))
            let narrow = geo.size.width < 760
            VStack(spacing: narrow ? 12 : 16) {
                header
                if store.status == .notConfigured {
                    ScrollView { SetupCard().padding(.top, 8) }
                } else {
                    HStack(alignment: .center, spacing: narrow ? 14 : 22) {
                        VStack(spacing: 12) {
                            HiFiDisplay()
                                .frame(maxHeight: max(110, knob - 6))
                            HStack {
                                HiFiTransport(keyWidth: narrow ? 44 : 54)
                                Spacer(minLength: 8)
                                HiFiMuteKey(store: store, width: narrow ? 64 : 72)
                            }
                        }
                        VolumeKnob(store: store, diameter: knob)
                    }
                    groove
                    VStack(alignment: .leading, spacing: 8) {
                        PanelLabel(text: "Input selector", size: 9)
                        HiFiSourceKeys(store: store)
                    }
                    groove
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            PanelLabel(text: "Presets", size: 9)
                            Spacer(minLength: 6)
                            SearchField(text: $model.searchText, isSearching: model.isSearching, prompt: "RECHERCHER…")
                                .frame(maxWidth: 240)
                            ExplorerButton(size: 14)
                            CurrentFavoriteButton(size: 14)
                            FavoritesMenu(size: 14)
                        }
                        ScrollView {
                            RadioContent { HiFiPresets() }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 2)
                        }
                        .scrollIndicators(.automatic)
                    }
                    .frame(minHeight: 70, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, narrow ? 18 : 26)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(BrushedMetal().ignoresSafeArea())
        .fontDesign(.monospaced)
        .foregroundStyle(HiFiPalette.text)
    }

    private var header: some View {
        let store = model.store
        return HStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(verbatim: "KEF")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(HiFiPalette.text)
                PanelLabel(text: model.speakerTitle, size: 11, color: HiFiPalette.text.opacity(0.85))
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                if model.isDemo {
                    PanelLabel(text: String(localized: "Démo"), size: 8, color: HiFiPalette.amber)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(HiFiPalette.amber.opacity(0.6), lineWidth: 1))
                }
            }
            Spacer()
            HStack(spacing: 6) {
                PanelLED(on: store.status != .notConfigured, color: ledColor(store.status))
                PanelLabel(text: store.status.isOnline ? (store.snapshot.modelLabel ?? String(localized: "Connectée")) : store.status.label, size: 9)
                if case .offline = store.status {
                    Button("RÉESSAYER") { store.retryNow() }
                        .buttonStyle(HiFiKeyStyle())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.leading, 4)
                }
            }
            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 26)
            }
            .buttonStyle(HiFiKeyStyle())
            .help("Réglages (⌘,)")
            .accessibilityLabel("Réglages")
            HiFiPowerButton(store: store)
        }
        .frame(height: 36)
    }

    /// Filet gravé entre deux zones de la façade.
    private var groove: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.black.opacity(0.6)).frame(height: 1)
            Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
        }
    }
}

// MARK: - Mini-lecteur

struct HiFiMiniPlayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PanelLED(on: store.status != .notConfigured, color: ledColor(store.status))
                Text(verbatim: "KEF").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2.5)
                PanelLabel(text: model.speakerTitle, size: 9, color: HiFiPalette.text.opacity(0.8))
                Spacer()
                OpenMainWindowButton {
                    Image(systemName: "macwindow").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 24)
                }
                .buttonStyle(HiFiKeyStyle())
                HiFiPowerButton(store: store, size: 26)
            }

            HiFiDisplay(compact: true)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    HiFiTransport(keyWidth: 40, keyHeight: 28)
                    HiFiMuteKey(store: store, width: 66)
                }
                Spacer(minLength: 0)
                VolumeKnob(store: store, diameter: 96, showsScale: false)
            }

            HiFiSourceKeys(store: store, height: 28, fontSize: 9)

            if !model.favorites.items.isEmpty {
                HiFiPresets(limit: 10, columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), compact: true)
            }

            MiniPlayerFooter(uppercase: true)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(HiFiPalette.secondary)
        }
        .padding(14)
        .frame(width: 320)
        .background(BrushedMetal())
        .fontDesign(.monospaced)
        .foregroundStyle(HiFiPalette.text)
    }
}
