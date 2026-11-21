import KEFKit
import SwiftUI

/// Barre de progression (masquée pour les flux sans durée : radio, entrées physiques).
struct PlaybackProgress: View {
    let store: SpeakerStore
    var compact = false

    var body: some View {
        let snap = store.snapshot
        if let duration = snap.player.durationMs, !snap.player.isLive, snap.isOn {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let position = store.estimatedPosition(at: context.date) ?? 0
                let fraction = duration > 0 ? min(1, Double(position) / Double(duration)) : 0
                VStack(spacing: compact ? 3 : 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.12))
                            Capsule().fill(.primary.opacity(0.75))
                                .frame(width: max(compact ? 3 : 4, geo.size.width * fraction))
                        }
                    }
                    .frame(height: compact ? 3 : 4)
                    .animation(.linear(duration: 0.5), value: fraction)
                    if !compact {
                        HStack {
                            Text(formatTime(position))
                            Spacer()
                            Text("-" + formatTime(max(0, duration - position)))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Progression")
        } else if snap.player.isLive && snap.isPlaying && !compact {
            HStack(spacing: 6) {
                EqualizerBars(animating: true, color: .kefAccent)
                Text("EN DIRECT").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(Color.kefAccent)
            }
            .frame(height: 22)
        }
    }
}

/// Précédent / lecture-pause / suivant. Sur une radio, précédent / suivant zappent entre
/// les favoris (cf. `AppModel.skipPlan`).
struct TransportControls: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 44

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let canControl = store.status.isOnline && snap.isOn
        let previous = model.skipPlan(.previous), next = model.skipPlan(.next)
        HStack(spacing: size * 0.5) {
            Button { model.skip(.previous) } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(CircleIconButtonStyle(size: size * 0.82))
            .disabled(!previous.isEnabled)
            .help(previous.help)
            .accessibilityLabel(previous.label)

            Button { Task { await store.playPause() } } label: {
                Image(systemName: snap.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: snap.isPlaying ? 0 : size * 0.03)
            }
            .buttonStyle(CircleIconButtonStyle(size: size * 1.2, prominent: true))
            .disabled(!canControl)
            .help(PlayPauseText.help(snap))
            .accessibilityLabel(PlayPauseText.label(snap))

            Button { model.skip(.next) } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(CircleIconButtonStyle(size: size * 0.82))
            .disabled(!next.isEnabled)
            .help(next.help)
            .accessibilityLabel(next.label)
        }
    }
}

/// Libellés VoiceOver d'une station (« Radio Cuivre, en cours »).
enum StationAccessibility {
    static func label(_ title: String, current: Bool, favorite: Bool = false) -> String {
        switch (current, favorite) {
        case (true, true): String(localized: "\(title), en cours, favori")
        case (true, false): String(localized: "\(title), en cours")
        case (false, true): String(localized: "\(title), favori")
        case (false, false): title
        }
    }
}

/// Libellés du bouton lecture / pause (une radio s'arrête puis reprend en direct).
enum PlayPauseText {
    static func label(_ snap: SpeakerSnapshot) -> String {
        snap.isPlaying ? (snap.player.isLive ? String(localized: "Arrêter la radio") : String(localized: "Pause")) : String(localized: "Lecture")
    }

    static func help(_ snap: SpeakerSnapshot) -> String {
        if snap.isPlaying && snap.player.isLive { return String(localized: "Arrêter la radio (Espace) : la reprise repart du direct") }
        return snap.isPlaying ? String(localized: "Pause (Espace)") : String(localized: "Lecture (Espace)")
    }
}

/// Curseur de volume + bouton couper le son.
struct VolumeControl: View {
    let store: SpeakerStore
    var showValue = true

    var body: some View {
        let snap = store.snapshot
        HStack(spacing: 10) {
            Button { store.toggleMute() } label: {
                Image(systemName: icon(snap))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .foregroundStyle(snap.isMuted ? Color.kefAccent : .secondary)
            .help(snap.isMuted ? "Rétablir le son" : "Couper le son")

            Slider(value: Binding(
                get: { Double(snap.volume) },
                set: { store.setVolume(Int($0.rounded())) }
            ), in: 0...100)
            .controlSize(.small)
            .tint(.kefAccent)
            .accessibilityLabel("Volume")

            if showValue {
                Text(verbatim: "\(snap.volume)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .disabled(!(store.status.isOnline && snap.isOn))
    }

    private func icon(_ snap: SpeakerSnapshot) -> String {
        if snap.isMuted { return "speaker.slash.fill" }
        switch snap.volume {
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// Bouton marche / veille.
struct PowerButton: View {
    let store: SpeakerStore
    var size: CGFloat = 32

    var body: some View {
        let on = store.snapshot.isOn
        Button { Task { await store.togglePower() } } label: {
            Image(systemName: "power")
        }
        .buttonStyle(CircleIconButtonStyle(size: size, prominent: on))
        .disabled(!store.status.isOnline)
        .help(on ? "Mettre en veille" : "Allumer")
        .accessibilityLabel(on ? "Mettre en veille" : "Allumer")
    }
}

/// Sélecteur d'entrée (SF Symbols).
struct SourcePicker: View {
    let store: SpeakerStore
    var compact = false

    var body: some View {
        let snap = store.snapshot
        HStack(spacing: compact ? 4 : 8) {
            ForEach(snap.sources) { source in
                let selected = snap.isOn && snap.source == source
                Button { Task { await store.selectSource(source) } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: source.symbol)
                            .font(.system(size: compact ? 13 : 16, weight: .medium))
                            .frame(height: compact ? 16 : 20)
                        if !compact {
                            Text(source.label).font(.caption2.weight(.medium)).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 7 : 10)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.8)))
                    .background {
                        RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Color.kefAccent.gradient) : AnyShapeStyle(.primary.opacity(0.06)))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
