// Génère l'icône de l'app (AppIcon.icns) sans dépendance externe :
// dessin Core Graphics → PNG à toutes les tailles → iconutil.
//
// Usage : swift scripts/make-icon.swift <dossier-de-sortie>
// Produit <dossier>/AppIcon.icns (et l'iconset intermédiaire).

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// Dessine l'icône sur une toile carrée de `size` pixels (grille macOS : 824/1024 de contenu).
func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    ctx.setShouldAntialias(true)

    // Plaque arrondie avec ombre portée.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.35))
    ctx.addPath(platePath)
    ctx.setFillColor(rgb(0x1C1D21))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x3A3C42), rgb(0x1E1F23), rgb(0x111214)], [0, 0.55, 1]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Reflet doux en haut.
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: 400, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 400, y: 900), endRadius: 520, options: [])
    ctx.restoreGState()

    let c = CGPoint(x: 512, y: 512)
    func circle(_ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

    // Saladier / anneau extérieur (caoutchouc sombre).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0x000000, 0.6))
    ctx.addEllipse(in: circle(300))
    ctx.setFillColor(rgb(0x0E0F11))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: circle(300))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x4A4C52), rgb(0x16171A)], [0, 1]),
                           start: CGPoint(x: 512, y: 812), end: CGPoint(x: 512, y: 212), options: [])
    ctx.restoreGState()

    // Suspension.
    ctx.addEllipse(in: circle(262))
    ctx.setFillColor(rgb(0x1A1B1E))
    ctx.fillPath()

    // Cône cuivré (Uni-Q) en dégradé radial.
    ctx.saveGState()
    ctx.addEllipse(in: circle(236))
    ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0xF6A262), rgb(0xE07434), rgb(0x9A451A), rgb(0x5E2A10)], [0, 0.35, 0.8, 1]),
                           startCenter: CGPoint(x: 470, y: 570), startRadius: 0,
                           endCenter: c, endRadius: 236, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Anneaux concentriques (guide d'onde « tangerine »).
    ctx.setLineWidth(5)
    for (r, a) in [(206.0, 0.22), (172.0, 0.18), (140.0, 0.25)] {
        ctx.addEllipse(in: circle(r))
        ctx.setStrokeColor(rgb(0x000000, a))
        ctx.strokePath()
        ctx.addEllipse(in: circle(r - 4))
        ctx.setStrokeColor(rgb(0xFFFFFF, a * 0.6))
        ctx.strokePath()
    }

    // Tweeter central (dôme doré).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: rgb(0x000000, 0.45))
    ctx.addEllipse(in: circle(96))
    ctx.setFillColor(rgb(0x2A1A10))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: circle(84))
    ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0xFFF1D6), rgb(0xE9B26C), rgb(0x8A5222)], [0, 0.45, 1]),
                           startCenter: CGPoint(x: 490, y: 540), startRadius: 0,
                           endCenter: c, endRadius: 84, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 2) }
}

for base in [16, 32, 128, 256, 512] {
    try writePNG(drawIcon(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(drawIcon(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let icns = outDir.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil a échoué\n".data(using: .utf8)!)
    exit(1)
}
print("Icône générée : \(icns.path)")
