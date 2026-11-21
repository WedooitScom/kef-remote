import KEFKit
import SwiftUI

// Pochette de repli et décor des tuiles de l'explorateur : petite scène « années 80 »
// (ciel de coucher de soleil, soleil rayé posé sur l'horizon, grille en perspective,
// palmiers en silhouette). Le détail s'adapte à la taille : lisible à 24 pt comme en grand.

struct SynthwaveArtView: View {
    let scene: Synthwave.Scene
    /// Grille et palmiers (désactivables pour un fond de tuile sous un texte).
    var showsPalms = true

    init(seed: Int, showsPalms: Bool = true) {
        scene = Synthwave.scene(seed: seed)
        self.showsPalms = showsPalms
    }

    init(key: String, showsPalms: Bool = true) {
        scene = Synthwave.scene(forKey: key)
        self.showsPalms = showsPalms
    }

    init(scene: Synthwave.Scene, showsPalms: Bool = true) {
        self.scene = scene
        self.showsPalms = showsPalms
    }

    var body: some View {
        Canvas { ctx, size in
            SynthwaveArt.draw(ctx, size: size, scene: scene, palms: showsPalms)
        }
        .accessibilityHidden(true)
    }
}

enum SynthwaveArt {
    static func draw(_ ctx: GraphicsContext, size: CGSize, scene: Synthwave.Scene, palms: Bool = true) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let s = min(w, h)
        let sky = scene.sky
        let hy = (h * scene.horizon).rounded()
        var ctx = ctx
        ctx.clip(to: Path(CGRect(origin: .zero, size: size)))

        // Ciel.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: hy)),
                 with: .linearGradient(Gradient(stops: [.init(color: Color(sky.top), location: 0),
                                                        .init(color: Color(sky.middle), location: 0.55),
                                                        .init(color: Color(sky.horizon), location: 1)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: hy)))

        // Soleil rayé : halo, disque en dégradé, bandes découpées vers le bas.
        let d = s * scene.sunSize
        let center = CGPoint(x: w * scene.sunX, y: hy - d * 0.18)
        let sunRect = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        ctx.fill(Path(ellipseIn: sunRect.insetBy(dx: -d * 0.35, dy: -d * 0.35)),
                 with: .radialGradient(Gradient(colors: [Color(sky.sunBottom).opacity(0.45), .clear]),
                                       center: center, startRadius: d * 0.3, endRadius: d * 0.85))
        ctx.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: hy)))
            layer.fill(Path(ellipseIn: sunRect),
                       with: .linearGradient(Gradient(colors: [Color(sky.sunTop), Color(sky.sunBottom)]),
                                             startPoint: CGPoint(x: 0, y: sunRect.minY), endPoint: CGPoint(x: 0, y: sunRect.maxY)))
            layer.blendMode = .destinationOut
            let bands = s < 40 ? 3 : 5
            for i in 0..<bands {
                let t = Double(i) / Double(bands)
                let y = center.y + d * (0.02 + t * 0.4)
                let bh = max(0.75, d * (0.018 + t * 0.05))
                layer.fill(Path(CGRect(x: sunRect.minX, y: y, width: d, height: bh)), with: .color(.black))
            }
        }

        // Sol nocturne et grille en perspective.
        ctx.fill(Path(CGRect(x: 0, y: hy, width: w, height: h - hy)),
                 with: .linearGradient(Gradient(colors: [Color(sky.ground), Color(Synthwave.night)]),
                                       startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: h)))
        let line = max(0.6, s * 0.011)
        var grid = Path()
        let vanishing = CGPoint(x: w / 2, y: hy)
        let columns = s < 40 ? 3 : 6
        for i in -columns...columns {
            let xb = w / 2 + CGFloat(i) * w * 0.2
            grid.move(to: CGPoint(x: vanishing.x + CGFloat(i) * w * 0.025, y: hy))
            grid.addLine(to: CGPoint(x: xb, y: h))
        }
        let rows = s < 40 ? 3 : 5
        for k in 1...rows {
            let t = Double(k) / Double(rows)
            let y = hy + (h - hy) * t * t
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: w, y: y))
        }
        ctx.stroke(grid, with: .color(Color(sky.grid).opacity(0.75)), lineWidth: line)
        // Horizon lumineux.
        ctx.fill(Path(CGRect(x: 0, y: hy - line / 2, width: w, height: line * 1.4)), with: .color(Color(sky.horizon)))

        // Palmiers en silhouette (pas en très petit).
        guard palms, s >= 40 else { return }
        let ink = Color(Synthwave.night)
        switch scene.palms {
        case .none: break
        case .left: palm(&ctx, base: CGPoint(x: w * 0.13, y: hy + (h - hy) * 0.25), height: s * 0.5, lean: 1, ink)
        case .right: palm(&ctx, base: CGPoint(x: w * 0.87, y: hy + (h - hy) * 0.25), height: s * 0.5, lean: -1, ink)
        case .both:
            palm(&ctx, base: CGPoint(x: w * 0.1, y: hy + (h - hy) * 0.3), height: s * 0.48, lean: 1, ink)
            palm(&ctx, base: CGPoint(x: w * 0.9, y: hy + (h - hy) * 0.2), height: s * 0.38, lean: -1, ink)
        }
    }

    /// Palmier : tronc courbe et six palmes.
    private static func palm(_ ctx: inout GraphicsContext, base: CGPoint, height: CGFloat, lean: CGFloat, _ color: Color) {
        let top = CGPoint(x: base.x + lean * height * 0.22, y: base.y - height)
        var trunk = Path()
        trunk.move(to: base)
        trunk.addQuadCurve(to: top, control: CGPoint(x: base.x - lean * height * 0.02, y: base.y - height * 0.6))
        ctx.stroke(trunk, with: .color(color), style: StrokeStyle(lineWidth: max(1, height * 0.06), lineCap: .round))
        let length = height * 0.5
        for angle in [-168.0, -135, -100, -62, -28, 8] {
            let a = angle * .pi / 180
            let end = CGPoint(x: top.x + cos(a) * length, y: top.y + sin(a) * length * 0.75 + length * 0.35)
            let mid = CGPoint(x: (top.x + end.x) / 2, y: (top.y + end.y) / 2 - length * 0.22)
            var leaf = Path()
            leaf.move(to: top)
            leaf.addQuadCurve(to: end, control: CGPoint(x: mid.x, y: mid.y - length * 0.08))
            leaf.addQuadCurve(to: top, control: CGPoint(x: mid.x, y: mid.y + length * 0.12))
            ctx.fill(leaf, with: .color(color))
        }
    }
}
