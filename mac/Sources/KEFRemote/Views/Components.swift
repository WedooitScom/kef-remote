import AppKit
import KEFKit
import SwiftUI

// MARK: - Thème

extension Color {
    /// Cuivre KEF (accent), lisible en clair comme en sombre.
    static let kefAccent = Color(red: 0.91, green: 0.45, blue: 0.22)
}

/// Résolution des URLs d'images renvoyées par l'enceinte.
enum ImageURL {
    static func resolve(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        // ATS : http autorisé pour le réseau local et *.airable.io (Info.plist) ; ailleurs, on tente https.
        if scheme == "http", let host = url.host?.lowercased(), !isAllowedHTTP(host) {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            c?.scheme = "https"
            return c?.url ?? url
        }
        return url
    }

    static func isAllowedHTTP(_ host: String) -> Bool {
        if host == "airable.io" || host.hasSuffix(".airable.io") || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1]))
            || octets[0] == 127 || (octets[0] == 169 && octets[1] == 254)
    }
}

/// Visuels générés du mode démo : `demo://art?hue=24`.
enum DemoArt {
    static func hue(from raw: String?) -> Int? {
        guard let raw, raw.hasPrefix("demo://art"), let c = URLComponents(string: raw),
              let v = c.queryItems?.first(where: { $0.name == "hue" })?.value else { return nil }
        return Int(v)
    }
}

/// Pochette de démonstration : pochette de repli (style du design courant, ou `style`)
/// dont la graine est la teinte de démo, cf. `FallbackArtworkView`.
struct DemoArtworkView: View {
    let hue: Int
    var style: ArtworkStyle?

    var body: some View {
        FallbackArtworkView(seed: hue, style: style)
    }
}

/// Image distante (http(s) ou démo) avec repli.
struct RemoteImage<Placeholder: View>: View {
    let source: String?
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let hue = DemoArt.hue(from: source) {
            DemoArtworkView(hue: hue)
        } else if let url = ImageURL.resolve(source) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholder()
                }
            }
        } else {
            placeholder()
        }
    }
}

/// Logo de station : fond clair (les logos airable sont souvent transparents).
struct StationLogo: View {
    let station: Station
    var cornerRadius: CGFloat = 14

    var body: some View {
        RemoteImage(source: station.icon) {
            // Sans logo : pochette de repli du design, stable d'après le nom.
            FallbackArtworkView(key: station.title, title: station.title)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func initials(_ title: String) -> String {
        title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Pochette de la piste en cours, ou visuel de l'entrée (TV, optique…), ou veille.
struct CoverArtwork: View {
    let snapshot: SpeakerSnapshot
    var cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            if !snapshot.isOn {
                placeholder(symbol: "power", caption: "En veille")
            } else if let source = snapshot.source, source != .wifi {
                placeholder(symbol: source.symbol, caption: source.label)
            } else if let cover = snapshot.player.coverURL ?? snapshot.player.station?.icon {
                RemoteImage(source: cover) { fallback }
                    .id(cover)
                    .transition(.opacity)
            } else {
                fallback
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.3), value: snapshot.player.coverURL)
    }

    /// Pas de pochette : pochette de repli du design, d'après la station (ou la piste).
    private var fallback: some View {
        let station = snapshot.player.station?.title
        return FallbackArtworkView(key: station ?? snapshot.player.title ?? snapshot.player.artist ?? "KEF", title: station)
    }

    private func placeholder(symbol: String, caption: String?) -> some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: geo.size.width * 0.04) {
                    Image(systemName: symbol)
                        .font(.system(size: geo.size.width * 0.26, weight: .light))
                    if let caption, geo.size.width > 120 {
                        Text(caption).font(.system(size: geo.size.width * 0.06, weight: .medium))
                    }
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

/// Fond translucide de fenêtre (vibrancy).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Petit égaliseur animé (station en cours).
struct EqualizerBars: View {
    var animating: Bool
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = animating ? (sin(t * (5 + Double(i) * 1.7) + Double(i)) + 1) / 2 : 0.35
                    Capsule().fill(color).frame(width: 2.5, height: 3 + 7 * phase)
                }
            }
            .frame(height: 10, alignment: .bottom)
        }
    }
}

/// Bouton rond translucide (transport, alimentation…).
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 36
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if prominent {
                    Circle().fill(Color.kefAccent.gradient)
                } else {
                    Circle().fill(.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Pastille d'état de connexion.
struct StatusDot: View {
    let status: ConnectionStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.6), radius: 3)
    }

    private var color: Color {
        switch status {
        case .online: .green
        case .connecting: .orange
        case .offline: .red
        case .notConfigured: .gray
        }
    }
}

extension ConnectionStatus {
    var label: String {
        switch self {
        case .online: "Connectée"
        case .connecting: "Connexion…"
        case .offline(let why): "Hors ligne · \(why)"
        case .notConfigured: "Aucune enceinte configurée"
        }
    }
}

/// « 3:07 » / « 1:02:03 ».
func formatTime(_ ms: Int?) -> String {
    guard let ms, ms >= 0 else { return "--:--" }
    let total = ms / 1000
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
