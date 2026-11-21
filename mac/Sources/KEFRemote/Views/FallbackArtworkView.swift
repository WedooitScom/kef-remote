import KEFKit
import SwiftUI

// Pochette de repli : dessinée quand il n'y a ni pochette ni logo (et pour la démo), dans
// le style du design courant (thème injecté) ou d'un style imposé. Stable par station.

struct FallbackArtworkView: View {
    /// Graine : teinte de démo, sinon dérivée de `key` (nom de station ou de piste).
    var seed: Int?
    var key: String?
    /// Titre pour le monogramme / l'initiale (station).
    var title: String?
    /// Style imposé (rendus hors écran, vignettes) ; sinon celui du design courant.
    var style: ArtworkStyle?
    @Environment(\.designTheme) private var theme

    var body: some View {
        let style = style ?? ArtworkStyle(theme.design)
        let seed = seed.map { UInt32(truncatingIfNeeded: $0) } ?? FallbackArtwork.seed(for: key ?? title ?? "")
        let spec = FallbackArtwork.spec(style: style, seed: seed, title: title)
        Group {
            if style == .neon80 {
                SynthwaveArtView(seed: Int(seed))
            } else {
                Canvas { ctx, size in FallbackArt.draw(ctx, size: size, spec: spec) }
            }
        }
        .accessibilityHidden(true)
    }
}

enum FallbackArt {
    static func draw(_ context: GraphicsContext, size: CGSize, spec: FallbackArtworkSpec) {
        var ctx = context
        ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
        switch spec.style {
        case .classique: classique(&ctx, size, spec)
        case .hifi: hifi(&ctx, size, spec)
        case .immersif: immersif(&ctx, size, spec)
        case .editorial: editorial(&ctx, size, spec)
        case .baladeur: baladeur(&ctx, size, spec)
        case .pixel: pixel(ctx, size, spec)
        case .neon80: SynthwaveArt.draw(ctx, size: size, scene: Synthwave.scene(seed: Int(spec.seed)))
        }
    }

    private static func c(_ spec: FallbackArtworkSpec, _ i: Int) -> Color { Color(spec.colors[i]) }

    /// Classique : dégradé vif, motif géométrique simple, initiale nette.
    private static func classique(_ ctx: inout GraphicsContext, _ size: CGSize, _ spec: FallbackArtworkSpec) {
        let w = size.width, h = size.height, s = min(w, h)
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [c(spec, 0), c(spec, 1)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
        let white = Color.white
        switch spec.variant {
        case 0:
            let r = s * 0.42
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.72 - r, y: h * 0.28 - r, width: 2 * r, height: 2 * r)),
                     with: .color(white.opacity(0.2)))
            let r2 = s * 0.16
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.3 - r2, y: h * 0.72 - r2, width: 2 * r2, height: 2 * r2)),
                     with: .color(white.opacity(0.14)))
        case 1:
            for i in 0..<3 {
                var band = Path()
                let o = CGFloat(i) * s * 0.26 + s * 0.1
                band.move(to: CGPoint(x: o, y: h))
                band.addLine(to: CGPoint(x: o + s * 0.12, y: h))
                band.addLine(to: CGPoint(x: o + s * 0.12 + h, y: 0))
                band.addLine(to: CGPoint(x: o + h, y: 0))
                band.closeSubpath()
                ctx.fill(band, with: .color(white.opacity(0.1 + Double(i) * 0.04)))
            }
        default:
            for i in 1...4 {
                let r = s * 0.24 * CGFloat(i)
                ctx.stroke(Path(ellipseIn: CGRect(x: -r, y: h - r, width: 2 * r, height: 2 * r)),
                           with: .color(white.opacity(0.22)), lineWidth: max(1, s * 0.03))
            }
        }
        if let initial = spec.initial, s >= 20 {
            ctx.draw(Text(String(initial)).font(.system(size: s * 0.42, weight: .bold, design: .rounded))
                        .foregroundStyle(white),
                     at: CGPoint(x: w / 2, y: h / 2))
        }
    }

    /// Hi-Fi : noir et ambre, vinyle ou VU-mètre.
    private static func hifi(_ ctx: inout GraphicsContext, _ size: CGSize, _ spec: FallbackArtworkSpec) {
        let w = size.width, h = size.height, s = min(w, h)
        let black = c(spec, 0), amber = c(spec, 1), groove = c(spec, 2), cream = c(spec, 3)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x2A2A2E), black]), center: CGPoint(x: w * 0.3, y: h * 0.2),
                                       startRadius: 0, endRadius: s))
        let center = CGPoint(x: w / 2, y: h / 2)
        if spec.variant < 2 {
            // Vinyle : sillons, étiquette ambre, reflet.
            let r = s * 0.44
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(black))
            var rr = r - s * 0.03
            while rr > s * 0.17 {
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr)),
                           with: .color(groove), lineWidth: max(0.5, s * 0.008))
                rr -= max(1.5, s * 0.035)
            }
            var sheen = Path()
            sheen.move(to: center)
            sheen.addArc(center: center, radius: r, startAngle: .degrees(-60 + spec.phase * 40), endAngle: .degrees(-30 + spec.phase * 40), clockwise: false)
            sheen.closeSubpath()
            ctx.fill(sheen, with: .color(.white.opacity(0.07)))
            let lr = s * 0.15
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - lr, y: center.y - lr, width: 2 * lr, height: 2 * lr)), with: .color(amber))
            if let initial = spec.initial, s >= 40 {
                ctx.draw(Text(String(initial)).font(.system(size: lr * 0.9, weight: .heavy, design: .monospaced)).foregroundStyle(black),
                         at: center)
            } else {
                let hr = max(1, s * 0.015)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - hr, y: center.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(black))
            }
        } else {
            // VU-mètre : cadran crème, graduation, zone rouge, aiguille.
            let face = CGRect(x: s * 0.1, y: h * 0.2, width: w - s * 0.2, height: h * 0.6)
            ctx.fill(Path(roundedRect: face, cornerRadius: s * 0.04), with: .linearGradient(
                Gradient(colors: [amber.opacity(0.95), Color(hex: 0xC27E22)]), startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.maxY)))
            let pivot = CGPoint(x: face.midX, y: face.maxY + face.height * 0.25)
            let radius = face.height * 0.95
            for i in 0...10 {
                let a = (-50 + Double(i) * 10) * .pi / 180
                let inner = radius * (i % 5 == 0 ? 0.8 : 0.86)
                var tick = Path()
                tick.move(to: CGPoint(x: pivot.x + sin(a) * inner, y: pivot.y - cos(a) * inner))
                tick.addLine(to: CGPoint(x: pivot.x + sin(a) * radius * 0.94, y: pivot.y - cos(a) * radius * 0.94))
                ctx.stroke(tick, with: .color(i >= 8 ? Color(hex: 0xB3261E) : black), lineWidth: max(0.75, s * 0.012))
            }
            let a = (-45 + spec.phase * 70) * .pi / 180
            var needle = Path()
            needle.move(to: pivot)
            needle.addLine(to: CGPoint(x: pivot.x + sin(a) * radius * 0.92, y: pivot.y - cos(a) * radius * 0.92))
            var clipped = ctx
            clipped.clip(to: Path(face))
            clipped.stroke(needle, with: .color(black), lineWidth: max(1, s * 0.015))
            if s >= 40 {
                ctx.draw(Text(verbatim: "VU").font(.system(size: s * 0.09, weight: .bold, design: .monospaced)).foregroundStyle(black),
                         at: CGPoint(x: face.midX, y: face.maxY - face.height * 0.22))
            }
            ctx.stroke(Path(roundedRect: face, cornerRadius: s * 0.04), with: .color(cream.opacity(0.4)), lineWidth: max(0.5, s * 0.008))
        }
    }

    /// Immersif : grands dégradés flous et doux, aspect verre.
    private static func immersif(_ ctx: inout GraphicsContext, _ size: CGSize, _ spec: FallbackArtworkSpec) {
        let w = size.width, h = size.height, s = min(w, h)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c(spec, 0)))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.16))
            let p = spec.phase
            let blobs: [(CGFloat, CGFloat, CGFloat, Int)] = [
                (0.25 + p * 0.2, 0.3, 0.55, 1), (0.8, 0.35 + p * 0.25, 0.5, 2), (0.45, 0.85, 0.6, 3),
            ]
            for (x, y, r, i) in blobs {
                let rr = s * r
                layer.fill(Path(ellipseIn: CGRect(x: w * x - rr / 2, y: h * y - rr / 2, width: rr, height: rr)),
                           with: .color(c(spec, i).opacity(0.9)))
            }
        }
        // Verre : reflet en haut, liseré clair.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.5)),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.5)))
        ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.18)), lineWidth: 1)
    }

    /// Éditorial : papier crème, monogramme, filets fins.
    private static func editorial(_ ctx: inout GraphicsContext, _ size: CGSize, _ spec: FallbackArtworkSpec) {
        let w = size.width, h = size.height, s = min(w, h)
        let paper = c(spec, 0), ink = c(spec, 1), accent = c(spec, 2)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
        let line = max(0.5, s * 0.008)
        let margin = s * 0.1
        ctx.fill(Path(CGRect(x: margin, y: h * 0.14, width: w - 2 * margin, height: line)), with: .color(ink))
        ctx.fill(Path(CGRect(x: margin, y: h * 0.86, width: w - 2 * margin, height: line)), with: .color(ink))
        if s >= 40 {
            ctx.fill(Path(CGRect(x: margin, y: h * 0.86 - line * 3, width: w - 2 * margin, height: line)), with: .color(ink.opacity(0.4)))
        }
        // Repère d'accent : carré, filet épais ou point.
        switch spec.variant {
        case 0: ctx.fill(Path(CGRect(x: margin, y: h * 0.2, width: s * 0.07, height: s * 0.07)), with: .color(accent))
        case 1: ctx.fill(Path(CGRect(x: margin, y: h * 0.14 - line * 2, width: (w - 2 * margin) * 0.35, height: line * 4)), with: .color(accent))
        default: ctx.fill(Path(ellipseIn: CGRect(x: w - margin - s * 0.07, y: h * 0.2, width: s * 0.07, height: s * 0.07)), with: .color(accent))
        }
        let letter = spec.initial.map(String.init) ?? "№"
        ctx.draw(Text(letter).font(.system(size: s * 0.5, weight: .black, design: .serif)).foregroundStyle(ink),
                 at: CGPoint(x: w / 2, y: h * 0.52))
    }

    /// Baladeur : pochette sobre façon lecteur, gris clair et note.
    private static func baladeur(_ ctx: inout GraphicsContext, _ size: CGSize, _ spec: FallbackArtworkSpec) {
        let w = size.width, h = size.height, s = min(w, h)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [c(spec, 0), c(spec, 1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        // Reflet diagonal discret.
        var sheen = Path()
        sheen.move(to: .zero)
        sheen.addLine(to: CGPoint(x: w * 0.62, y: 0))
        sheen.addLine(to: CGPoint(x: 0, y: h * 0.62))
        sheen.closeSubpath()
        ctx.fill(sheen, with: .color(.white.opacity(0.35)))
        var note = ctx.resolve(Image(systemName: spec.variant == 2 ? "music.note.list" : "music.note"))
        note.shading = .color(Color(hex: 0x8E99A6))
        let side = s * 0.46
        var shaded = ctx
        shaded.addFilter(.shadow(color: .black.opacity(0.18), radius: s * 0.02, y: s * 0.01))
        shaded.draw(note, in: CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side))
        // Liseré d'accent en bas (bleu, gris ou vert).
        ctx.fill(Path(CGRect(x: 0, y: h - max(1.5, s * 0.03), width: w, height: max(1.5, s * 0.03))), with: .color(c(spec, 2)))
    }

    /// Rétro pixel : petite scène sur une grille de 12 × 12 pixels, à l'échelle entière.
    private static func pixel(_ ctx: GraphicsContext, _ size: CGSize, _ spec: FallbackArtworkSpec) {
        let k = CGFloat(max(1, PixelScale.fit(CGSize(width: 12, height: 12), in: size, range: 1...64)))
        let bg = c(spec, 0), ink = c(spec, 1), paper = c(spec, 2)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
        var c2 = ctx
        c2.translateBy(x: PixelScale.centered(12 * k, in: size.width), y: PixelScale.centered(12 * k, in: size.height))
        let p = PixelPainter(ctx: c2, k: k)
        // Motif de fond : bandes, damier ou soleil.
        switch spec.variant {
        case 0: for y in stride(from: 1, to: 12, by: 3) { p.fill(0, y, 12, 1, paper.opacity(0.45)) }
        case 1: for y in 0..<12 { for x in 0..<12 where (x + y) % 4 == 0 { p.fill(x, y, 1, 1, paper.opacity(0.45)) } }
        default: p.disc(5, 0, 7, paper.opacity(0.55))
        }
        if let initial = spec.initial, PixelFont.covers(initial) {
            let glyph = PixelFont.glyph(for: initial)
            p.notched(PixelRect(2, 1, 9, 11), ink)
            p.fill(3, 2, 7, 9, paper)
            p.text(String(initial), x: 3 + (7 - glyph.width) / 2, top: 3 - PixelFont.capTop, ink)
        } else {
            let note = PixelIcon.note
            p.icon(note, x: (12 - note.width) / 2, y: (12 - note.height) / 2, ink: ink)
        }
    }
}
