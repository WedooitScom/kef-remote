import KEFKit
import SwiftUI

// Design « Rétro pixel » : un radio-cassette en pixel art, dessiné en code sur une grille
// de pixels logiques (rectangles alignés, aucune image). Un pixel logique occupe un nombre
// entier de points (`PixelScale`), d'où des contours nets à toutes les tailles de fenêtre.
// Contours sombres épais, aplats pastel, une seule couleur de reflet par face.

// MARK: - Palette

/// Couleurs du poste et de l'interface autour. `off` : poste éteint (aplats grisés).
struct PixelPalette {
    var bg, ink, shadow: Color
    var body, bodyHi, bodyLo: Color
    var teal, tealHi, tealLo: Color
    var mustard, mustardHi, mustardLo: Color
    var slate, slateHi, slateLo: Color
    var glass, paper, chrome: Color
    var key, keyHi, keyLo: Color
    var red, redHi, redLo: Color
    var led, ledText, ledOff: Color
    // Interface (texte, cartes)
    var text, secondary, card, cardHover, accent: Color

    init(dark: Bool, off: Bool = false) {
        func c(_ light: UInt32, _ night: UInt32) -> Color { Self.tone(dark ? night : light, gray: off) }
        func ui(_ light: UInt32, _ night: UInt32) -> Color { Color(hex: dark ? night : light) }
        bg = ui(0xF5EBD6, 0x1C2033)
        ink = ui(0x2A2238, 0x0B0A12)
        shadow = ui(0xD9C8A8, 0x10121F)
        body = c(0xF0A3B4, 0xB8708A); bodyHi = c(0xFAD3DB, 0xD996AB); bodyLo = c(0xD07E93, 0x8C4F67)
        teal = c(0x7ED3C8, 0x4F9C94); tealHi = c(0xBDEEE6, 0x7CC3BA); tealLo = c(0x4FA79D, 0x356F69)
        mustard = c(0xEDC15B, 0xC9A246); mustardHi = c(0xF9E09A, 0xE6C676); mustardLo = c(0xC59532, 0x957424)
        slate = c(0x5C6E96, 0x46557A); slateHi = c(0x8C9DC0, 0x6A7BA3); slateLo = c(0x3F4E72, 0x2E3A58)
        glass = c(0x2C3352, 0x141829); paper = c(0xFFF7E4, 0xE9DDC2); chrome = c(0xD9DDE6, 0xA9AFBD)
        key = c(0xFFF4DC, 0xDCD0B4); keyHi = c(0xFFFFFF, 0xF2E8D2); keyLo = c(0xCDBFA3, 0x9F937B)
        red = c(0xF0545F, 0xE5525D); redHi = c(0xFF9CA2, 0xFF8B93); redLo = c(0xB33A44, 0x9E2F39)
        led = c(0x8CF08C, 0x8CF08C); ledText = c(0xFFC861, 0xFFCF70); ledOff = c(0x3A4263, 0x232842)
        text = ui(0x2A2238, 0xF1E6CF)
        secondary = ui(0x6B5E73, 0xA9A3B8)
        card = ui(0xFFF7E4, 0x2A304A)
        cardHover = ui(0xF8E7C6, 0x343B5A)
        accent = ui(0xB02F5B, 0xF59AB3)
    }

    /// Aplat grisé (poste éteint) : luminance, contraste légèrement adouci.
    static func tone(_ hex: UInt32, gray: Bool) -> Color {
        guard gray else { return Color(hex: hex) }
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        let l = 0.299 * r + 0.587 * g + 0.114 * b
        let soft = 0.5 + (l - 0.5) * 0.85
        func mix(_ v: Double) -> Double { soft * 0.9 + v * 0.1 }
        return Color(.sRGB, red: mix(r), green: mix(g), blue: mix(b))
    }

    static func of(_ scheme: ColorScheme, off: Bool = false) -> PixelPalette {
        PixelPalette(dark: scheme == .dark, off: off)
    }

    /// Couleurs dynamiques (thème injecté, champ de recherche, explorateur).
    enum Dynamic {
        static let bg = Color.dynamic(light: 0xF5EBD6, dark: 0x1C2033)
        static let ink = Color.dynamic(light: 0x2A2238, dark: 0x0B0A12)
        static let text = Color.dynamic(light: 0x2A2238, dark: 0xF1E6CF)
        static let secondary = Color.dynamic(light: 0x6B5E73, dark: 0xA9A3B8)
        static let card = Color.dynamic(light: 0xFFF7E4, dark: 0x2A304A)
        static let accent = Color.dynamic(light: 0xB02F5B, dark: 0xF59AB3)
        static let favorite = Color.dynamic(light: 0xC98300, dark: 0xF2C14E)
    }

    /// Aplats pastel des tuiles (explorateur), choisis selon la teinte.
    static let pastels: [UInt32] = [0xF2A7B5, 0xF5B98A, 0xEDC15B, 0xA8DDA0, 0x7ED3C8, 0x9DB0D8, 0xC5B3E6]

    static func pastel(hue: Int) -> Color {
        let h = (hue % 360 + 360) % 360
        return Color(hex: pastels[h * pastels.count / 360])
    }
}

// MARK: - Dessin sur la grille

/// Dessine des rectangles sur la grille des pixels logiques (`k` points par pixel).
struct PixelPainter {
    let ctx: GraphicsContext
    let k: CGFloat

    func cg(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGRect {
        CGRect(x: CGFloat(x) * k, y: CGFloat(y) * k, width: CGFloat(w) * k, height: CGFloat(h) * k)
    }

    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color) {
        guard w > 0, h > 0 else { return }
        ctx.fill(Path(cg(x, y, w, h)), with: .color(color))
    }

    func fill(_ r: PixelRect, _ color: Color) { fill(r.x, r.y, r.w, r.h, color) }

    func fill(_ rects: [PixelRect], _ color: Color) {
        var path = Path()
        for r in rects where r.w > 0 && r.h > 0 { path.addRect(cg(r.x, r.y, r.w, r.h)) }
        ctx.fill(path, with: .color(color))
    }

    /// Rectangle aux coins coupés d'un pixel.
    func notched(_ r: PixelRect, _ color: Color) {
        fill([PixelRect(r.x + 1, r.y, r.w - 2, r.h), PixelRect(r.x, r.y + 1, r.w, r.h - 2)], color)
    }

    /// Boîte : contour sombre, aplat, reflet en haut à gauche, ombre en bas à droite.
    func box(_ r: PixelRect, fill color: Color, ink: Color, hi: Color? = nil, lo: Color? = nil) {
        notched(r, ink)
        let i = r.inset(1)
        notched(i, color)
        if let lo {
            fill(i.x + 1, i.maxY - 1, i.w - 2, 1, lo)
            fill(i.maxX - 1, i.y + 1, 1, i.h - 2, lo)
        }
        if let hi {
            fill(i.x + 1, i.y, i.w - 2, 1, hi)
            fill(i.x, i.y + 1, 1, i.h - 3, hi)
        }
    }

    /// Disque de diamètre `d` dont le carré englobant commence en (`x`, `y`).
    func disc(_ x: Int, _ y: Int, _ d: Int, _ color: Color) {
        var path = Path()
        for (row, span) in PixelArt.discSpans(diameter: d).enumerated() where !span.isEmpty {
            path.addRect(cg(x + span.lowerBound, y + row, span.count, 1))
        }
        ctx.fill(path, with: .color(color))
    }

    /// Disque centré dans le carré `square` (diamètres de même parité que le carré).
    func centeredDisc(_ square: PixelRect, _ d: Int, _ color: Color, dx: Int = 0, dy: Int = 0) {
        disc(square.x + (square.w - d) / 2 + dx, square.y + (square.h - d) / 2 + dy, d, color)
    }

    /// Disque avec un croissant de reflet en haut à gauche (un seul reflet par face).
    func shadedDisc(_ square: PixelRect, _ d: Int, _ color: Color, hi: Color) {
        centeredDisc(square, d, hi)
        centeredDisc(square, d - 2, color, dx: 1, dy: 1)
    }

    /// Texte bitmap ; `top` = haut de la cellule (accents compris, capitales 2 lignes plus bas).
    func text(_ string: String, x: Int, top: Int, _ color: Color) {
        var path = Path()
        for (gx, glyph) in PixelFont.layout(string) {
            for row in 0..<glyph.rows.count where glyph.rows[row] != 0 {
                var col = 0
                while col < glyph.width {
                    guard glyph.isOn(x: col, y: row) else { col += 1; continue }
                    var end = col
                    while end < glyph.width && glyph.isOn(x: end, y: row) { end += 1 }
                    path.addRect(cg(x + gx + col, top + row, end - col, 1))
                    col = end
                }
            }
        }
        ctx.fill(path, with: .color(color))
    }

    func icon(_ icon: PixelIcon, x: Int, y: Int, ink: Color, fill: Color? = nil) {
        var inkPath = Path(), fillPath = Path()
        for row in 0..<icon.height {
            for col in 0..<icon.width {
                switch icon.ink(x: col, y: row) {
                case .ink: inkPath.addRect(cg(x + col, y + row, 1, 1))
                case .fill: fillPath.addRect(cg(x + col, y + row, 1, 1))
                case .none: break
                }
            }
        }
        if let fill { ctx.fill(fillPath, with: .color(fill)) }
        ctx.fill(inkPath, with: .color(ink))
    }

    /// Image réduite (`side × side` couleurs, ligne par ligne) à partir de (`x`, `y`).
    func pixels(_ colors: [SRGBColor], side: Int, x: Int, y: Int) {
        guard colors.count == side * side else { return }
        for row in 0..<side {
            var col = 0
            while col < side {
                let c = colors[row * side + col]
                var end = col + 1
                while end < side && colors[row * side + end] == c { end += 1 }
                fill(x + col, y + row, end - col, 1, Color(c))
                col = end
            }
        }
    }

    /// Ligne épaisse (antenne) : tracé de Bresenham, contour puis âme claire.
    func rod(from a: (x: Int, y: Int), to b: (x: Int, y: Int), ink: Color, core: Color) {
        var points: [(Int, Int)] = []
        var x0 = a.x, y0 = a.y
        let dx = abs(b.x - x0), sx = x0 < b.x ? 1 : -1
        let dy = -abs(b.y - y0), sy = y0 < b.y ? 1 : -1
        var err = dx + dy
        while true {
            points.append((x0, y0))
            if x0 == b.x && y0 == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
        fill(points.map { PixelRect($0.0 - 1, $0.1 - 1, 3, 3) }, ink)
        fill(points.map { PixelRect($0.0, $0.1, 1, 1) }, core)
    }

    /// Peintre limité à un rectangle (défilement des titres).
    func clipped(to r: PixelRect) -> PixelPainter {
        var c = ctx
        c.clip(to: Path(cg(r.x, r.y, r.w, r.h)))
        return PixelPainter(ctx: c, k: k)
    }
}

// MARK: - Petites vues bitmap

/// Texte en police bitmap 5×7, à l'échelle entière `scale`.
struct PixelText: View {
    let text: String
    var scale: CGFloat = 2
    var color: Color

    var body: some View {
        let width = PixelFont.width(of: text)
        Canvas { ctx, _ in
            PixelPainter(ctx: ctx, k: scale).text(text, x: 0, top: 0, color)
        }
        .frame(width: CGFloat(width) * scale, height: CGFloat(PixelFont.cellHeight) * scale)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// Titre bitmap (échelle 3, sinon 2), repli en monospace gras si la place manque.
struct PixelTitle: View {
    let text: String
    var color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            PixelText(text: text, scale: 3, color: color)
            PixelText(text: text, scale: 2, color: color)
            Text(text.interfaceUppercased)
                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(2)
        }
    }
}

struct PixelIconView: View {
    let icon: PixelIcon
    var scale: CGFloat = 2
    var ink: Color
    var fill: Color?

    var body: some View {
        Canvas { ctx, _ in
            PixelPainter(ctx: ctx, k: scale).icon(icon, x: 0, y: 0, ink: ink, fill: fill)
        }
        .frame(width: CGFloat(icon.width) * scale, height: CGFloat(icon.height) * scale)
        .accessibilityHidden(true)
    }
}

/// Logo ou pochette réduit à `side × side` pixels (cadre sombre d'un pixel).
struct PixelThumb: View {
    let source: String?
    let title: String
    var side = 10
    var unit: CGFloat = 3
    @Environment(\.colorScheme) private var scheme
    @State private var colors: [SRGBColor]?

    var body: some View {
        let pal = PixelPalette.of(scheme)
        let hue = RadioCatalog.stableHue(title)
        Canvas { ctx, _ in
            let p = PixelPainter(ctx: ctx, k: unit)
            p.fill(0, 0, side + 2, side + 2, pal.ink)
            if let colors {
                p.pixels(colors, side: side, x: 1, y: 1)
            } else {
                // En attendant (ou sans logo) : aplat pastel et initiale.
                p.fill(1, 1, side, side, PixelPalette.pastel(hue: hue))
                if side >= 7, let first = PixelFont.normalize(title).first(where: { $0.isLetter || $0.isNumber }) {
                    let glyph = PixelFont.glyph(for: first)
                    p.text(String(first), x: 1 + (side - glyph.width) / 2,
                           top: 1 + (side - PixelFont.capHeight) / 2 - PixelFont.capTop, pal.ink)
                }
            }
        }
        .overlay {
            // Visuel généré (démo) ou absent : pochette de repli en pixel art.
            if source == nil || DemoArt.hue(from: source) != nil {
                FallbackArtworkView(seed: DemoArt.hue(from: source), key: title, title: title, style: .pixel)
                    .frame(width: CGFloat(side) * unit, height: CGFloat(side) * unit)
            }
        }
        .frame(width: CGFloat(side + 2) * unit, height: CGFloat(side + 2) * unit)
        .task(id: source) {
            colors = await CoverColors.shared.pixelArt(for: source, side: side)
        }
        .accessibilityHidden(true)
    }
}

/// Afficheur LED : texte bitmap qui défile s'il est trop long.
struct PixelLEDStrip: View {
    let text: String
    var unit: CGFloat = 2
    @Environment(\.colorScheme) private var scheme
    @State private var start = Date()

    var body: some View {
        let pal = PixelPalette.of(scheme)
        let height = PixelFont.cellHeight + 4
        GeometryReader { geo in
            let boxW = Int(geo.size.width / unit)
            let inner = boxW - 6
            let tw = PixelFont.width(of: text)
            let scrolls = PixelMarquee.scrolls(textWidth: tw, boxWidth: inner)
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !scrolls)) { tl in
                Canvas { ctx, _ in
                    let p = PixelPainter(ctx: ctx, k: unit)
                    p.box(PixelRect(0, 0, boxW, height), fill: pal.glass, ink: pal.ink)
                    let off = PixelMarquee.offset(textWidth: tw, boxWidth: inner, time: tl.date.timeIntervalSince(start))
                    let clip = p.clipped(to: PixelRect(3, 1, inner, height - 2))
                    clip.text(text, x: 3 - off, top: 2, pal.ledText)
                    if scrolls { clip.text(text, x: 3 - off + tw + PixelMarquee.gap, top: 2, pal.ledText) }
                }
            }
        }
        .frame(height: CGFloat(height) * unit)
        .onChange(of: text) { start = .now }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// Fond de panneau : boîte aux coins coupés, contour sombre, ombre portée franche.
private struct PixelPanelBackground: View {
    var fill: Color
    var unit: CGFloat = 3
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = PixelPalette.of(scheme)
        Canvas { ctx, size in
            let p = PixelPainter(ctx: ctx, k: unit)
            let w = Int(size.width / unit), h = Int(size.height / unit)
            p.notched(PixelRect(1, 1, w - 1, h - 1), pal.shadow)
            p.box(PixelRect(0, 0, w - 1, h - 1), fill: fill, ink: pal.ink)
        }
    }
}

extension View {
    func pixelPanel(fill: Color, unit: CGFloat = 3) -> some View {
        background(PixelPanelBackground(fill: fill, unit: unit))
    }
}

// MARK: - Touches

/// Touche en pixel art : contour sombre, aplat, reflet en haut, chant plus foncé ; enfoncée
/// (ou verrouillée, `latched`) elle descend d'un pixel. Avec `icon`, l'icône est dessinée
/// sur la grille (le libellé du bouton est ignoré, sauf pour l'accessibilité).
struct PixelKeyStyle: ButtonStyle {
    var unit: CGFloat
    var face: Color
    var hi: Color
    var lo: Color
    var ink: Color
    var icon: PixelIcon?
    var iconFill: Color?
    var latched = false

    func makeBody(configuration: Configuration) -> some View {
        PixelKeyBody(configuration: configuration, style: self)
    }
}

private struct PixelKeyBody: View {
    let configuration: ButtonStyleConfiguration
    let style: PixelKeyStyle
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let down = configuration.isPressed || style.latched
        let u = style.unit
        let content = Group {
            if style.icon == nil {
                configuration.label
                    .padding(.horizontal, u * 3)
                    // La cellule bitmap a 2 lignes d'accents en haut et 1 de jambage en bas.
                    .padding(.top, down ? u * 2 : u)
                    .padding(.bottom, down ? u * 2 : u * 3)
                    .opacity(isEnabled ? 1 : 0.45)
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        content
            .background {
                Canvas { ctx, size in
                    let p = PixelPainter(ctx: ctx, k: u)
                    let w = Int((size.width / u).rounded()), h = Int((size.height / u).rounded())
                    p.notched(PixelRect(0, 0, w, h), style.ink)
                    let face: PixelRect
                    if down {
                        p.fill(1, 1, w - 2, 1, style.lo)
                        face = PixelRect(1, 2, w - 2, h - 3)
                        p.fill(face, style.face)
                    } else {
                        face = PixelRect(1, 1, w - 2, h - 3)
                        p.fill(face, style.face)
                        p.fill(2, 1, w - 4, 1, style.hi)
                        p.fill(1, h - 2, w - 2, 1, style.lo)
                    }
                    if let icon = style.icon {
                        p.icon(icon, x: face.x + (face.w - icon.width) / 2, y: face.y + (face.h - icon.height + 1) / 2,
                               ink: isEnabled ? style.ink : style.lo, fill: style.iconFill)
                    }
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.06), value: down)
    }
}

extension ButtonStyle where Self == PixelKeyStyle {
    static func ivory(_ pal: PixelPalette, unit: CGFloat, icon: PixelIcon?, latched: Bool = false) -> PixelKeyStyle {
        PixelKeyStyle(unit: unit, face: pal.key, hi: pal.keyHi, lo: pal.keyLo, ink: pal.ink, icon: icon, latched: latched)
    }

    static func mustard(_ pal: PixelPalette, unit: CGFloat, icon: PixelIcon?, fill: Color? = nil, latched: Bool = false) -> PixelKeyStyle {
        PixelKeyStyle(unit: unit, face: pal.mustard, hi: pal.mustardHi, lo: pal.mustardLo, ink: pal.ink, icon: icon,
                      iconFill: fill, latched: latched)
    }

    static func teal(_ pal: PixelPalette, unit: CGFloat, icon: PixelIcon? = nil, fill: Color? = nil, latched: Bool = false) -> PixelKeyStyle {
        PixelKeyStyle(unit: unit, face: pal.teal, hi: pal.tealHi, lo: pal.tealLo, ink: pal.ink, icon: icon,
                      iconFill: fill, latched: latched)
    }

    static func red(_ pal: PixelPalette, unit: CGFloat, icon: PixelIcon?) -> PixelKeyStyle {
        PixelKeyStyle(unit: unit, face: pal.red, hi: pal.redHi, lo: pal.redLo, ink: pal.ink, icon: icon)
    }
}

// MARK: - Radio-cassette

/// Ce que montre le poste à un instant donné.
struct BoomboxState {
    var on: Bool
    var playing: Bool
    var volume: Int
    var muted: Bool
    var band: String
    var title: String
    var subtitle: String
    var led: Color
}

/// Dessin du poste (hors touches, qui sont de vrais boutons posés par-dessus).
enum BoomboxArt {
    static func draw(_ p: PixelPainter, _ L: BoomboxLayout, _ s: BoomboxState, face c: PixelPalette,
                     live: PixelPalette, cover: [SRGBColor]?, time t: Double) {
        let frame = Int(t * 12)
        let beat = s.playing && (frame / 3) % 2 == 0
        let compact = L.compact

        // Ombre portée du boîtier.
        p.notched(L.body.offset(2, 2), live.shadow)

        // Antenne (derrière le boîtier) : déployée quand le poste est allumé.
        let base = (x: L.antennaBase.midX, y: L.antennaBase.y + 1)
        let tip = s.on ? L.antennaTip : (x: base.x, y: base.y - L.antennaRetractedLength)
        p.rod(from: base, to: tip, ink: c.ink, core: c.chrome)
        if s.on {
            p.fill(tip.x - 1, tip.y - 1, 3, 3, c.ink)
            p.fill(tip.x, tip.y, 1, 1, c.red)
        }
        p.box(L.antennaBase, fill: c.chrome, ink: c.ink)

        drawHandle(p, L.handle, thickness: compact ? 5 : 7, c, live)

        // Boîtier : rose, bande basse turquoise.
        p.box(L.body, fill: c.body, ink: c.ink, hi: c.bodyHi, lo: c.bodyLo)
        let inner = L.body.inset(1)
        let bandTop = (L.speakers.map(\.maxY).max() ?? inner.maxY) + (compact ? 1 : 2)
        p.fill(inner.x, bandTop, inner.w, 1, c.ink)
        p.fill([PixelRect(inner.x, bandTop + 1, inner.w, inner.maxY - 1 - (bandTop + 1)),
                PixelRect(inner.x + 1, inner.maxY - 1, inner.w - 2, 1)], c.teal)
        p.fill(inner.x + 1, bandTop + 1, inner.w - 2, 1, c.tealHi)
        p.fill(inner.x + 1, inner.maxY - 1, inner.w - 2, 1, c.tealLo)

        drawDial(p, L, s, c)
        for speaker in L.speakers { drawSpeaker(p, speaker, beat: beat, c) }
        drawCassette(p, L, s, c, cover: cover, frame: s.playing ? frame : 0, time: t)

        // Logement des touches piano.
        if let first = L.pianoKeys.first, let last = L.pianoKeys.last {
            p.fill(first.x - 1, first.y - 1, last.maxX - first.x + 2, first.h + 1, c.ink)
        }

        // Plaque « KEF » et voyant d'état.
        let b = L.badge
        let ledSize = compact ? 3 : 4
        let ledY = b.y + (compact ? 2 : 4)
        p.fill(b.x, ledY, ledSize, ledSize, c.ink)
        p.fill(b.x + 1, ledY + 1, ledSize - 2, ledSize - 2, s.on ? s.led : c.ledOff)
        p.text("KEF", x: b.x + ledSize + 3, top: b.y + (compact ? -1 : 2), c.ink)

        drawMeter(p, L.meter, playing: s.playing, frame: frame, c)
    }

    private static func drawHandle(_ p: PixelPainter, _ r: PixelRect, thickness t: Int, _ c: PixelPalette, _ live: PixelPalette) {
        // Contour : barre du haut et montants.
        p.fill([PixelRect(r.x + 1, r.y, r.w - 2, t), PixelRect(r.x, r.y + 1, t, r.h - 1),
                PixelRect(r.maxX - t, r.y + 1, t, r.h - 1)], c.ink)
        // Aplats.
        p.fill([PixelRect(r.x + 1, r.y + 1, r.w - 2, t - 2), PixelRect(r.x + 1, r.y + 1, t - 2, r.h - 1),
                PixelRect(r.maxX - t + 1, r.y + 1, t - 2, r.h - 1)], c.mustard)
        p.fill(r.x + 2, r.y + 1, r.w - 4, 1, c.mustardHi)
        p.fill(r.x + 1, r.y + 2, 1, r.h - 2, c.mustardHi)
        // Poignée caoutchouc au milieu.
        let gripW = r.w / 3
        p.fill(r.midX - gripW / 2, r.y, gripW, t, c.ink)
        p.fill(r.midX - gripW / 2 + 1, r.y + 1, gripW - 2, t - 2, c.slate)
        p.fill(r.midX - gripW / 2 + 1, r.y + 1, gripW - 2, 1, c.slateHi)
    }

    private static func drawDial(_ p: PixelPainter, _ L: BoomboxLayout, _ s: BoomboxState, _ c: PixelPalette) {
        let compact = L.compact
        p.box(L.dial, fill: c.glass, ink: c.ink)
        // Séparateur bande / graduation.
        p.fill(L.band.maxX + 1, L.dial.y + 1, 1, L.dial.h - 2, c.ink)
        let band = s.muted && s.on ? "MUTE" : s.band
        let bw = PixelFont.width(of: band)
        let bandTop = compact ? L.band.y - PixelFont.capTop : L.band.y + 3 - PixelFont.capTop
        p.text(band, x: L.band.x + (L.band.w - bw) / 2, top: bandTop, s.on ? (s.muted ? c.red : c.ledText) : c.slate)

        // Graduation : 21 traits (11 en compact), traits majeurs numérotés 0…10.
        let sc = L.scale
        let segments = compact ? 10 : 20
        let majorEvery = segments / 5
        for i in 0...segments {
            let x = sc.x + Int((Double(i) * Double(sc.w - 1) / Double(segments)).rounded())
            let major = i % majorEvery == 0
            p.fill(x, sc.y, 1, major ? (compact ? 2 : 3) : 1, s.on ? c.paper : c.slate)
            if major && !compact {
                let label = "\(i / majorEvery * 2)"
                let lw = PixelFont.width(of: label)
                let lx = min(max(sc.x, x - lw / 2), sc.maxX - lw)
                p.text(label, x: lx, top: sc.y + 5 - PixelFont.capTop, s.on ? c.slateHi : c.slate)
            }
        }
        if compact {
            p.fill(sc.x, sc.maxY - 2, sc.w, 1, c.slateLo)
        }
        // Aiguille = volume.
        let nx = L.needleX(volume: s.volume)
        p.fill(nx, sc.y - 1, 1, sc.h + 2, s.on ? c.red : c.slateHi)
        if !compact { p.fill(nx - 1, sc.maxY, 3, 1, s.on ? c.red : c.slateHi) }
    }

    private static func drawSpeaker(_ p: PixelPainter, _ r: PixelRect, beat: Bool, _ c: PixelPalette) {
        let d = r.w
        // Diamètres : contour, suspension, contour, membrane, cône, cache-noyau (pairs).
        let small = d < 40
        let surround = d - 2, ring = small ? d - 8 : d - 10
        let pulse = beat ? 2 : 0
        let cone = (small ? d - 16 : d - 20) + pulse
        let capRing = (small ? d - 20 : d - 32) + pulse
        p.centeredDisc(r, d, c.ink)
        p.shadedDisc(r, surround, c.teal, hi: c.tealHi)
        // Vis de fixation sur la suspension.
        let off = small ? 8 : 14
        let cx = r.x + d / 2, cy = r.y + d / 2
        p.fill([PixelRect(cx - off - 1, cy - off - 1, 1, 1), PixelRect(cx + off, cy - off - 1, 1, 1),
                PixelRect(cx - off - 1, cy + off, 1, 1), PixelRect(cx + off, cy + off, 1, 1)], c.tealLo)
        p.centeredDisc(r, ring, c.ink)
        p.shadedDisc(r, ring - 2, c.slate, hi: c.slateHi)
        p.centeredDisc(r, cone, c.slateLo)
        p.centeredDisc(r, capRing, c.ink)
        p.shadedDisc(r, capRing - 2, c.mustard, hi: c.mustardHi)
    }

    private static func drawCassette(_ p: PixelPainter, _ L: BoomboxLayout, _ s: BoomboxState, _ c: PixelPalette,
                                     cover: [SRGBColor]?, frame: Int, time: Double) {
        let win = L.cassetteWindow
        p.box(win, fill: c.glass, ink: c.ink)
        p.box(L.cassette, fill: c.slate, ink: c.ink, hi: c.slateHi, lo: c.slateLo)
        // Vis de la coque.
        let k = L.cassette.inset(2)
        p.fill([PixelRect(k.x, k.y, 1, 1), PixelRect(k.maxX - 1, k.y, 1, 1),
                PixelRect(k.x, k.maxY - 1, 1, 1), PixelRect(k.maxX - 1, k.maxY - 1, 1, 1)], c.slateLo)

        if let label = L.label {
            p.box(label, fill: c.paper, ink: c.ink)
            p.fill(label.x + 1, label.maxY - 3, label.w - 2, 1, c.body)
            p.fill(label.x + 1, label.maxY - 2, label.w - 2, 1, c.teal)
            let box = PixelRect(label.x + 2, label.y + 1, label.w - 4, label.h - 4)
            marquee(p, s.title, box: box, top: label.y + 1, color: c.ink, time: time)
            marquee(p, s.subtitle, box: box, top: label.y + 11, color: s.on ? c.slateLo : c.slate, time: time)
        } else {
            // Compact : étiquette sans texte, deux bandes.
            let strip = PixelRect(L.cassette.x + 3, L.cassette.y + 2, L.cassette.w - 6, L.reelWindow.y - L.cassette.y - 3)
            p.fill(strip, c.paper)
            p.fill(strip.x, strip.maxY - 1, strip.w, 1, c.body)
        }

        p.box(L.reelWindow, fill: c.glass, ink: c.ink)
        for reel in L.reels { drawReel(p, reel, frame: frame, c) }

        // Pochette pixelisée (ou note de musique).
        let cv = L.cover
        p.fill(cv, c.ink)
        let side = cv.w - 2
        if let cover, s.on {
            p.pixels(cover, side: side, x: cv.x + 1, y: cv.y + 1)
        } else {
            p.fill(cv.inset(1), s.on ? c.mustard : c.slate)
            let note = PixelIcon.note
            if side >= note.width {
                p.icon(note, x: cv.x + 1 + (side - note.width) / 2, y: cv.y + 1 + (side - note.height) / 2, ink: c.ink)
            }
        }

        // Reflet unique de la vitre (diagonale).
        let len = L.compact ? 5 : 9
        p.fill((0..<len).map { PixelRect(win.maxX - 5 - $0, win.y + 2 + $0, 2, 1) }, .white.opacity(0.22))
    }

    /// Texte de l'étiquette : défilement si trop long (texte répété pour boucler).
    private static func marquee(_ p: PixelPainter, _ text: String, box: PixelRect, top: Int, color: Color, time: Double) {
        let tw = PixelFont.width(of: text)
        let clip = p.clipped(to: PixelRect(box.x, top, box.w, PixelFont.cellHeight))
        if tw <= box.w {
            clip.text(text, x: box.x + (box.w - tw) / 2, top: top, color)
        } else {
            let off = PixelMarquee.offset(textWidth: tw, boxWidth: box.w, time: time)
            clip.text(text, x: box.x - off, top: top, color)
            clip.text(text, x: box.x - off + tw + PixelMarquee.gap, top: top, color)
        }
    }

    /// Bobine : bande enroulée sombre, moyeu clair, axe et une dent qui tourne.
    private static func drawReel(_ p: PixelPainter, _ r: PixelRect, frame: Int, _ c: PixelPalette) {
        p.centeredDisc(r, r.w, c.slateLo)
        let hub = r.w >= 12 ? 8 : 6
        p.centeredDisc(r, hub, c.paper)
        p.centeredDisc(r, 2, c.ink)
        // Dents du moyeu : deux pixels opposés qui tournent (45° par image).
        let radius = Double(hub) / 2 - 1
        let cx = Double(r.x) + Double(r.w) / 2, cy = Double(r.y) + Double(r.h) / 2
        var teeth: [PixelRect] = []
        for j in 0..<2 {
            let a = (Double(frame % 8) * 45 + Double(j) * 180) * .pi / 180
            teeth.append(PixelRect(Int(floor(cx + sin(a) * radius)), Int(floor(cy - cos(a) * radius)), 1, 1))
        }
        p.fill(teeth, c.ink)
    }

    private static func drawMeter(_ p: PixelPainter, _ m: PixelRect, playing: Bool, frame: Int, _ c: PixelPalette) {
        p.box(m, fill: c.glass, ink: c.ink)
        let inner = m.inset(1)
        let n = m.w >= 36 ? 8 : 6
        let segW = (inner.w - (n - 1)) / n
        let x0 = inner.x + (inner.w - (segW * n + n - 1)) / 2
        // Niveau pseudo-aléatoire, stable pour une image donnée.
        var seed = UInt32(truncatingIfNeeded: frame / 2) &* 2_654_435_761
        seed ^= seed >> 13
        let lit = playing ? 2 + Int(seed % UInt32(n - 1)) : 0
        for i in 0..<n {
            let color: Color
            if i >= lit { color = c.ledOff }
            else if i >= n - 1 { color = c.red }
            else if i >= n - 3 { color = c.mustard }
            else { color = c.led }
            p.fill(x0 + i * (segW + 1), inner.y + 1, segW, inner.h - 2, color)
        }
    }
}

/// Le radio-cassette complet : dessin animé + touches et cadran interactifs.
struct PixelBoombox: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let layout: BoomboxLayout
    let k: CGFloat
    @State private var cover: [SRGBColor]?
    @State private var titleStart = Date()

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        let on = store.status.isOnline && snap.isOn
        let live = PixelPalette.of(scheme)
        let face = PixelPalette.of(scheme, off: !on)
        let title = NowPlayingText.title(model)
        let subtitle = NowPlayingText.subtitle(model)
        let state = BoomboxState(on: on, playing: on && snap.isPlaying, volume: snap.volume, muted: snap.isMuted,
                                 band: on ? (snap.source ?? .wifi).panelLabel : "OFF",
                                 title: title, subtitle: subtitle, led: statusColor(store.status, live))
        let labelWidth = (layout.label?.w ?? 0) - 4
        let overflow = layout.label != nil
            && (PixelFont.width(of: title) > labelWidth || PixelFont.width(of: subtitle) > labelWidth)
        let coverSource = NowPlayingText.cover(model)
        let size = layout.size

        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !(state.playing || overflow))) { tl in
                let t = tl.date.timeIntervalSince(titleStart)
                Canvas { ctx, _ in
                    BoomboxArt.draw(PixelPainter(ctx: ctx, k: k), layout, state, face: face, live: live,
                                    cover: cover, time: t)
                }
            }
            .frame(width: CGFloat(size.w) * k, height: CGFloat(size.h) * k)
            .accessibilityElement()
            .accessibilityLabel("Radio-cassette")
            .accessibilityValue(Text(verbatim: "\(title), \(subtitle)"))

            topKeys(face: face, on: on)
            dial(enabled: on)
            pianoKeys(live: live, face: face, on: on)
        }
        .frame(width: CGFloat(size.w) * k, height: CGFloat(size.h) * k, alignment: .topLeading)
        .onChange(of: title) { titleStart = .now }
        .task(id: coverSource) {
            cover = await CoverColors.shared.pixelArt(for: coverSource, side: layout.cover.w - 2)
        }
    }

    private func place(_ r: PixelRect) -> (CGSize, CGPoint) {
        (CGSize(width: CGFloat(r.w) * k, height: CGFloat(r.h) * k), CGPoint(x: CGFloat(r.x) * k, y: CGFloat(r.y) * k))
    }

    @ViewBuilder
    private func topKeys(face: PixelPalette, on: Bool) -> some View {
        let store = model.store
        let keys = layout.topKeys
        if keys.count > 0 {
            let muted = store.snapshot.isMuted
            key(keys[0]) {
                Button { store.toggleMute() } label: { Color.clear }
                    .accessibilityLabel(muted ? "Rétablir le son" : "Couper le son")
                    .buttonStyle(.mustard(face, unit: k, icon: muted ? .mute : .speaker, latched: muted && on))
                    .disabled(!on)
                    .help(muted ? "Rétablir le son" : "Couper le son")
            }
        }
        if keys.count > 1 {
            let current = store.snapshot.currentStation
            let favorite = model.favorites.contains(current)
            key(keys[1]) {
                Button { model.toggleCurrentFavorite() } label: { Color.clear }
                .accessibilityLabel(favorite ? "Retirer la radio en cours" : "Ajouter la radio en cours")
                .buttonStyle(.mustard(face, unit: k, icon: .smallStar, latched: favorite))
                .disabled(current == nil)
                .help(current.map { favorite ? "Retirer « \($0.title) » des favoris" : "Ajouter « \($0.title) » aux favoris" }
                      ?? "Aucune radio airable en cours")
            }
        }
        if keys.count > 2 {
            key(keys[2]) {
                Button { model.toggleExplorer() } label: { Color.clear }
                    .accessibilityLabel("Explorer les radios")
                    .buttonStyle(.mustard(face, unit: k, icon: .globe, fill: face.teal, latched: model.showsExplorer))
                    .disabled(!model.store.hasClient)
                    .help("Explorer les radios par pays, genre et langue (⌘E)")
            }
        }
    }

    /// Cadran : l'aiguille suit le volume ; glisser, molette, flèches, VoiceOver (curseur
    /// fin commun, rendu invisible et posé sur la graduation).
    private func dial(enabled: Bool) -> some View {
        let sc = layout.scale
        let height = CGFloat(layout.dial.h) * k
        return ThinVolumeSlider(store: model.store, track: .clear, fill: .clear, thickness: 1, knob: max(14, height - 6))
            .frame(width: CGFloat(sc.w) * k, height: height)
            .offset(x: CGFloat(sc.x) * k, y: CGFloat(layout.dial.y) * k)
            .help("Volume : faites glisser l'aiguille du cadran, molette ou flèches")
    }

    @ViewBuilder
    private func pianoKeys(live: PixelPalette, face: PixelPalette, on: Bool) -> some View {
        let store = model.store
        let snap = store.snapshot
        let keys = layout.pianoKeys
        let compact = layout.compact
        let previous = model.skipPlan(.previous), next = model.skipPlan(.next)
        if keys.count == 4 {
            key(keys[0]) {
                Button { model.skip(.previous) } label: { Color.clear }
                    .accessibilityLabel(previous.label)
                    .buttonStyle(.ivory(face, unit: k, icon: compact ? .previousSmall : .previous))
                    .disabled(!previous.isEnabled)
                    .help(previous.help)
            }
            key(keys[1]) {
                let playing = snap.isPlaying && on
                let icon: PixelIcon = playing ? (compact ? .pauseSmall : .pause) : (compact ? .playSmall : .play)
                Button { Task { await store.playPause() } } label: { Color.clear }
                    .accessibilityLabel(PlayPauseText.label(snap))
                    .buttonStyle(.ivory(face, unit: k, icon: icon, latched: playing))
                    .disabled(!on)
                    .help(PlayPauseText.help(snap))
            }
            key(keys[2]) {
                Button { model.skip(.next) } label: { Color.clear }
                    .accessibilityLabel(next.label)
                    .buttonStyle(.ivory(face, unit: k, icon: compact ? .nextSmall : .next))
                    .disabled(!next.isEnabled)
                    .help(next.help)
            }
            key(keys[3]) {
                // Touche d'allumage : toujours en couleur, même poste éteint.
                Button { Task { await store.togglePower() } } label: { Color.clear }
                    .accessibilityLabel(on ? "Mettre en veille" : "Allumer")
                    .buttonStyle(.red(live, unit: k, icon: compact ? .powerSmall : .power))
                    .disabled(!store.status.isOnline)
                    .help(on ? "Mettre en veille" : "Allumer")
            }
        }
    }

    private func key<Content: View>(_ r: PixelRect, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: CGFloat(r.w) * k, height: CGFloat(r.h) * k)
            .offset(x: CGFloat(r.x) * k, y: CGFloat(r.y) * k)
    }
}

/// Couleur du voyant d'état.
private func statusColor(_ status: ConnectionStatus, _ pal: PixelPalette) -> Color {
    switch status {
    case .online: pal.led
    case .connecting: pal.mustard
    case .offline: pal.red
    case .notConfigured: pal.ledOff
    }
}

// MARK: - Sources

private struct PixelSourceKeys: View {
    let store: SpeakerStore
    var showsLabel = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = PixelPalette.of(scheme)
        let snap = store.snapshot
        HStack(spacing: 6) {
            if showsLabel {
                PixelText(text: String(localized: "SOURCE"), scale: 2, color: pal.secondary)
                    .padding(.trailing, 4)
            }
            ForEach(snap.sources) { source in
                let selected = snap.isOn && snap.source == source
                Button { Task { await store.selectSource(source) } } label: {
                    PixelText(text: source.panelLabel, scale: 2, color: pal.ink)
                }
                .buttonStyle(selected ? PixelKeyStyle.mustard(pal, unit: 2, icon: nil, latched: true) : PixelKeyStyle.teal(pal, unit: 2))
                .help(source.label)
                .accessibilityLabel("Source \(source.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .disabled(!store.status.isOnline)
    }
}

// MARK: - Favoris

private struct PixelFavoritesList: View {
    @Environment(AppModel.self) private var model
    @State private var dropTarget: String?

    var body: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(model.favorites.items.enumerated()), id: \.element.id) { index, station in
                PixelFavoriteRow(station: station, index: index, dropTarget: $dropTarget)
            }
        }
        .animation(.spring(duration: 0.3), value: model.favorites.items)
    }
}

private struct PixelFavoriteRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let station: Station
    let index: Int
    @Binding var dropTarget: String?
    @State private var hovering = false

    var body: some View {
        let pal = PixelPalette.of(scheme)
        let current = model.isCurrent(station)
        HStack(spacing: 10) {
            PixelThumb(source: station.icon, title: station.title, side: 10, unit: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.title)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(current ? pal.ink : pal.text)
                    .lineLimit(1)
                if let d = station.description {
                    Text(d)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(current ? pal.ink.opacity(0.7) : pal.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if model.store.loadingStationID == station.id {
                ProgressView().controlSize(.mini)
            } else if current {
                EqualizerBars(animating: model.store.snapshot.isPlaying, color: pal.ink)
            }
            if hovering {
                Button { model.toggleFavorite(station) } label: {
                    PixelIconView(icon: .star, scale: 2, ink: pal.ink, fill: pal.mustard)
                }
                .buttonStyle(.plain)
                .help("Retirer « \(station.title) » des favoris")
                .accessibilityLabel("Retirer \(station.title) des favoris")
            }
            if index < 9 {
                PixelText(text: "\(index + 1)", scale: 2, color: current ? pal.ink : pal.secondary)
                    .help(Text(verbatim: "⌘\(index + 1)"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            if current {
                PixelPanelBackground(fill: pal.mustard, unit: 2)
            } else if hovering {
                Rectangle().fill(pal.cardHover)
            }
        }
        .overlay {
            if dropTarget == station.id {
                Rectangle().strokeBorder(pal.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .favoriteInteractions(station: station, index: index, dropTarget: $dropTarget)
        .help(station.description ?? station.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StationAccessibility.label(station.title, current: current))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Retirer des favoris") { model.toggleFavorite(station) }
    }
}

/// Panneau des favoris : titre, explorateur, étoile, recherche, liste.
private struct PixelFavoritesPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        let pal = PixelPalette.of(scheme)
        let current = model.store.snapshot.currentStation
        let favorite = model.favorites.contains(current)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                PixelText(text: String(localized: "FAVORIS"), scale: 2, color: pal.text)
                if !model.favorites.items.isEmpty {
                    PixelText(text: "\(model.favorites.items.count)", scale: 2, color: pal.secondary)
                }
                Spacer(minLength: 4)
                Button { model.toggleExplorer() } label: { Color.clear }
                    .accessibilityLabel("Explorer les radios")
                    .buttonStyle(.teal(pal, unit: 2, icon: .globe, fill: pal.tealHi, latched: model.showsExplorer))
                    .frame(width: 26, height: 24)
                    .disabled(!model.store.hasClient)
                    .help("Explorer les radios par pays, genre et langue (⌘E)")
                Button { model.toggleCurrentFavorite() } label: { Color.clear }
                .accessibilityLabel(favorite ? "Retirer la radio en cours" : "Ajouter la radio en cours")
                .buttonStyle(.mustard(pal, unit: 2, icon: .star, fill: favorite ? pal.paper : pal.mustardLo, latched: favorite))
                .frame(width: 26, height: 24)
                .disabled(current == nil)
                .help(current.map { favorite ? "Retirer « \($0.title) » des favoris" : "Ajouter « \($0.title) » aux favoris" }
                      ?? "Aucune radio airable en cours")
                FavoritesMenu(size: 14)
            }
            SearchField(text: $model.searchText, isSearching: model.isSearching)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            ScrollView {
                RadioContent { PixelFavoritesList() }
                    .padding(.vertical, 2)
                    .padding(.trailing, 2)
            }
            .scrollIndicators(.automatic)
        }
        .padding(14)
        .padding(.trailing, 3)
        .padding(.bottom, 3)
        .pixelPanel(fill: pal.card)
        .foregroundStyle(pal.text)
    }
}

// MARK: - Fenêtre principale

struct PixelMainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let pal = PixelPalette.of(scheme)
        let store = model.store
        let layout = BoomboxLayout.regular
        let logical = CGSize(width: layout.size.w, height: layout.size.h)
        GeometryReader { geo in
            let wide = geo.size.width >= 860
            let panelWidth = min(400, max(300, geo.size.width * 0.34))
            VStack(spacing: 14) {
                header(pal)
                if store.status == .notConfigured {
                    ScrollView { SetupCard().padding(.top, 8) }
                } else if wide {
                    let avail = CGSize(width: geo.size.width - panelWidth - 64,
                                       height: geo.size.height - 36 - 14 - 36 - 120)
                    let k = CGFloat(PixelScale.fit(logical, in: avail, range: 2...5))
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 18) {
                            Spacer(minLength: 0)
                            PixelBoombox(layout: layout, k: k)
                            PixelLEDStrip(text: NowPlayingText.kicker(model) + "  ·  " + NowPlayingText.subtitle(model), unit: 2)
                                .frame(width: CGFloat(layout.size.w - 4) * k)
                            PixelSourceKeys(store: store)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        PixelFavoritesPanel()
                            .frame(width: panelWidth)
                    }
                } else {
                    let avail = CGSize(width: geo.size.width - 32, height: (geo.size.height - 36 - 14 - 40) * 0.6)
                    let k = CGFloat(PixelScale.fit(logical, in: avail, range: 2...5))
                    PixelBoombox(layout: layout, k: k)
                    ViewThatFits(in: .horizontal) {
                        PixelSourceKeys(store: store)
                        PixelSourceKeys(store: store, showsLabel: false)
                        ScrollView(.horizontal) { PixelSourceKeys(store: store, showsLabel: false) }
                            .scrollIndicators(.never)
                    }
                    PixelFavoritesPanel()
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, wide ? 24 : 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(pal.bg.ignoresSafeArea())
        .foregroundStyle(pal.text)
    }

    private func header(_ pal: PixelPalette) -> some View {
        let store = model.store
        return HStack(spacing: 10) {
            Canvas { ctx, _ in
                let p = PixelPainter(ctx: ctx, k: 3)
                p.fill(0, 0, 4, 4, pal.ink)
                p.fill(1, 1, 2, 2, statusColor(store.status, pal))
            }
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                PixelText(text: model.speakerTitle, scale: 2, color: pal.text)
                Text(model.speakerTitle.interfaceUppercased)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
            }
            .layoutPriority(-1)
            if model.isDemo && !RadioCatalog.fold(model.speakerTitle).contains(RadioCatalog.fold(String(localized: "Démo"))) {
                PixelText(text: String(localized: "DÉMO"), scale: 2, color: pal.ink)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .pixelPanel(fill: pal.mustard, unit: 2)
            }
            Spacer(minLength: 8)
            if store.status.isOnline, let label = store.snapshot.modelLabel {
                PixelText(text: label, scale: 2, color: pal.secondary)
            } else {
                Text(store.status.label.interfaceUppercased)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(pal.secondary)
            }
            if case .offline = store.status {
                Button { store.retryNow() } label: { PixelText(text: String(localized: "RÉESSAYER"), scale: 2, color: pal.ink) }
                    .buttonStyle(.mustard(pal, unit: 2, icon: nil))
            }
            Button { openSettings() } label: { Color.clear }
                .accessibilityLabel("Réglages")
                .buttonStyle(.teal(pal, unit: 2, icon: .gear, fill: pal.tealHi))
                .frame(width: 26, height: 24)
                .help("Réglages (⌘,)")
        }
        .frame(height: 30)
    }
}

// MARK: - Mini-lecteur

struct PixelMiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 7), count: 6)

    var body: some View {
        let pal = PixelPalette.of(scheme)
        let store = model.store
        let layout = BoomboxLayout.compactLayout
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Canvas { ctx, _ in
                    let p = PixelPainter(ctx: ctx, k: 2)
                    p.fill(0, 0, 4, 4, pal.ink)
                    p.fill(1, 1, 2, 2, statusColor(store.status, pal))
                }
                .frame(width: 8, height: 8)
                Text(model.speakerTitle.interfaceUppercased)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 4)
                OpenMainWindowButton { Color.clear }
                    .buttonStyle(.teal(pal, unit: 2, icon: .window, fill: pal.tealHi))
                    .frame(width: 24, height: 22)
            }

            PixelBoombox(layout: layout, k: 2)

            PixelLEDStrip(text: NowPlayingText.compactTitle(model) + "  ·  " + NowPlayingText.compactSubtitle(model), unit: 2)

            if !model.favorites.items.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                    ForEach(model.favorites.items.prefix(12)) { station in
                        let current = model.isCurrent(station)
                        Button { model.play(station) } label: {
                            PixelThumb(source: station.icon, title: station.title, side: 8, unit: 3)
                                .overlay {
                                    if store.loadingStationID == station.id { ProgressView().controlSize(.mini) }
                                }
                                .padding(2)
                                .background { if current { Rectangle().fill(pal.accent) } }
                        }
                        .buttonStyle(.plain)
                        .help(station.title)
                        .accessibilityLabel(StationAccessibility.label(station.title, current: current))
                    }
                }
            }

            MiniPlayerFooter()
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(pal.secondary)
        }
        .padding(10)
        .frame(width: 240)
        .background(pal.bg)
        .foregroundStyle(pal.text)
    }
}

// MARK: - Vignette (sélecteur de styles)

/// Petit poste sur une grille de 22 × 15 pixels, à l'échelle entière qui tient.
struct PixelThumbnailArt: View {
    var body: some View {
        Canvas { ctx, size in
            let pal = PixelPalette(dark: false)
            let k = CGFloat(max(1, PixelScale.fit(CGSize(width: 22, height: 15), in: size, range: 1...8)))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pal.bg))
            var c = ctx
            c.translateBy(x: PixelScale.centered(22 * k, in: size.width), y: PixelScale.centered(15 * k, in: size.height))
            let p = PixelPainter(ctx: c, k: k)
            // Poignée, boîtier, haut-parleurs, cassette, touches.
            p.fill(7, 1, 8, 1, pal.ink)
            p.fill(7, 1, 1, 3, pal.ink)
            p.fill(14, 1, 1, 3, pal.ink)
            p.fill(17, 1, 1, 3, pal.ink)
            p.box(PixelRect(1, 3, 20, 11), fill: pal.body, ink: pal.ink, hi: pal.bodyHi)
            p.fill(3, 5, 16, 1, pal.glass)
            p.disc(2, 7, 5, pal.ink)
            p.disc(3, 8, 3, pal.teal)
            p.disc(15, 7, 5, pal.ink)
            p.disc(16, 8, 3, pal.teal)
            p.fill(8, 7, 6, 4, pal.ink)
            p.fill(9, 8, 4, 2, pal.mustard)
            p.fill(8, 12, 6, 1, pal.key)
        }
        .accessibilityHidden(true)
    }
}
