import CoreGraphics
import CoreImage
import Foundation

// MARK: - Choix du design

/// Designs de l'interface (fenêtre principale et mini-lecteur). Seule la présentation
/// change : l'état, les commandes et les favoris sont communs.
public enum AppDesign: String, CaseIterable, Identifiable, Sendable {
    case classique, hifi, immersif, editorial, baladeur, pixel, neon

    public var id: String { rawValue }

    /// Clé UserDefaults (`@AppStorage`).
    public static let storageKey = "appDesign"
    public static let defaultDesign = AppDesign.classique

    /// Nom affiché (menus, réglages).
    public var label: String {
        switch self {
        case .classique: localized("Classique")
        case .hifi: localized("Hi-Fi analogique")
        case .immersif: localized("Pochette immersive")
        case .editorial: localized("Éditorial")
        case .baladeur: localized("Baladeur")
        case .pixel: localized("Rétro pixel")
        case .neon: localized("Néon 80")
        }
    }

    /// Description courte (aide des vignettes de réglage).
    public var summary: String {
        switch self {
        case .classique: localized("Le design d'origine, translucide et sobre.")
        case .hifi: localized("Façade d'ampli : molette de volume, touches, vumètre.")
        case .immersif: localized("La pochette en grand, couleurs tirées de l'image.")
        case .editorial: localized("Grande typographie, filets fins, accent orange.")
        case .baladeur: localized("Écran rétro et molette cliquable.")
        case .pixel: localized("Radio-cassette en pixel art : cadran, cassette, touches piano.")
        case .neon: localized("Affiche synthwave : coucher de soleil, grille, palmiers, néons rose et cyan.")
        }
    }

    /// Analyse tolérante (ligne de commande `--design`, valeur stockée) : casse, accents,
    /// tirets et quelques synonymes anglais.
    public static func parse(_ raw: String?) -> AppDesign? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch s {
        case "classique", "classic", "default", "defaut": return .classique
        case "hifi", "hifianalogique", "analog", "analogique", "ampli": return .hifi
        case "immersif", "immersive", "pochette", "pochetteimmersive", "cover": return .immersif
        case "editorial": return .editorial
        case "baladeur", "ipod", "retro", "mp3": return .baladeur
        case "pixel", "retropixel", "pixelart", "8bit", "boombox", "radiocassette", "cassette": return .pixel
        case "neon", "neon80", "neons", "synthwave", "retrowave", "miami", "annees80", "80s": return .neon
        default: return nil
        }
    }

    /// Valeur stockée → design (repli sur le design par défaut si absente ou inconnue).
    public static func stored(_ raw: String?) -> AppDesign {
        parse(raw) ?? defaultDesign
    }
}

// MARK: - Molette cliquable (design Baladeur)

/// Géométrie de la molette cliquable : zones de clic, crans de rotation, fenêtre de liste.
public enum ClickWheelGeometry {
    /// Zones cliquables de l'anneau.
    public enum Zone: Sendable, Equatable {
        case menu, next, playPause, previous
    }

    /// Rotation (degrés) correspondant à un cran.
    public static let notch = 18.0

    /// Zone sous un angle (0° en haut, sens horaire, cf. `KnobGeometry.angle(of:around:)`).
    public static func zone(forAngle angle: Double) -> Zone {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a <= -180 { a += 360 }
        switch a {
        case -45..<45: return .menu
        case 45..<135: return .next
        case -135 ..< -45: return .previous
        default: return .playPause
        }
    }

    /// Crans entiers contenus dans une rotation cumulée ; renvoie aussi le reste.
    public static func notches(in accumulated: Double) -> (steps: Int, remainder: Double) {
        let steps = Int((accumulated / notch).rounded(.towardZero))
        return (steps, accumulated - Double(steps) * notch)
    }

    /// Lignes visibles d'une liste de `count` éléments dont `visible` tiennent à l'écran,
    /// la sélection restant autant que possible au milieu.
    public static func window(selection: Int, count: Int, visible: Int) -> Range<Int> {
        guard count > 0, visible > 0 else { return 0..<0 }
        guard count > visible else { return 0..<count }
        let sel = min(max(selection, 0), count - 1)
        let top = min(max(0, sel - visible / 2), count - visible)
        return top..<(top + visible)
    }
}

// MARK: - Molette de volume

/// Géométrie de la molette rotative (design Hi-Fi) : course de 270°, de -135° (minimum,
/// en bas à gauche) à +135° (maximum, en bas à droite), 0° = index en haut, sens horaire.
public enum KnobGeometry {
    public static let minAngle = -135.0
    public static let maxAngle = 135.0
    public static var sweep: Double { maxAngle - minAngle }

    /// Valeur → angle (degrés), la valeur étant bornée à `range`.
    public static func angle(forValue value: Double, in range: ClosedRange<Double> = 0...100) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return minAngle }
        let t = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
        return minAngle + t * sweep
    }

    /// Angle (degrés) → valeur, l'angle étant borné à la course de la molette.
    public static func value(forAngle angle: Double, in range: ClosedRange<Double> = 0...100) -> Double {
        let a = min(max(angle, minAngle), maxAngle)
        return range.lowerBound + (a - minAngle) / sweep * (range.upperBound - range.lowerBound)
    }

    /// Angle d'un point autour du centre, en coordonnées d'écran (y vers le bas) :
    /// 0° en haut, 90° à droite, ±180° en bas.
    public static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        return atan2(dx, -dy) * 180 / .pi
    }

    /// Plus petite rotation signée (degrés, dans -180…180) pour aller de `from` à `to`.
    public static func delta(from: Double, to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Variation de valeur pour une rotation de `degrees` (course complète = toute la plage).
    public static func valueDelta(forRotation degrees: Double, in range: ClosedRange<Double> = 0...100) -> Double {
        degrees / sweep * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Couleur dominante d'une pochette

/// Couleur RVB (composantes 0…1, espace sRGB).
public struct SRGBColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Luminance relative WCAG.
    public var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// Rapport de contraste WCAG avec une autre couleur (1…21).
    public func contrastRatio(with other: SRGBColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public static let white = SRGBColor(red: 1, green: 1, blue: 1)

    /// Teinte, saturation, luminosité (0…1).
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxC > 0 ? delta / maxC : 0, maxC)
    }

    public init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }
}

/// Extraction de la couleur d'ambiance d'une pochette (design « Pochette immersive »).
public enum DominantColor {
    /// Fond neutre quand il n'y a pas d'image.
    public static let fallback = SRGBColor(red: 0.16, green: 0.17, blue: 0.19)

    /// Couleur moyenne de l'image (filtre Core Image `CIAreaAverage`), sans gestion de
    /// couleur (valeurs brutes de l'image).
    public static func average(of image: CGImage) -> SRGBColor? {
        let input = CIImage(cgImage: image)
        guard !input.extent.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: input.extent),
              ]),
              let output = filter.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let alpha = Double(pixel[3]) / 255
        guard alpha > 0.01 else { return nil }
        // Sortie prémultipliée : on rapporte à l'opacité.
        return SRGBColor(red: min(1, Double(pixel[0]) / 255 / alpha),
                        green: min(1, Double(pixel[1]) / 255 / alpha),
                        blue: min(1, Double(pixel[2]) / 255 / alpha))
    }

    /// Couleur de fond tirée d'une couleur moyenne : saturation légèrement relevée (une
    /// moyenne est souvent terne), puis assombrie jusqu'à garantir un contraste d'au moins
    /// `minContrast` avec du texte blanc.
    public static func background(from color: SRGBColor, minContrast: Double = 7) -> SRGBColor {
        var (h, s, b) = color.hsb
        s = min(0.8, s * 1.3)
        b = min(max(b, 0.12), 0.42)
        var result = SRGBColor(hue: h, saturation: s, brightness: b)
        while result.contrastRatio(with: .white) < minContrast && b > 0.05 {
            b *= 0.9
            result = SRGBColor(hue: h, saturation: s, brightness: b)
        }
        return result
    }

    /// Raccourci : image → couleur de fond (repli neutre si l'image est vide ou transparente).
    public static func backgroundColor(for image: CGImage?) -> SRGBColor {
        guard let image, let average = average(of: image) else { return fallback }
        return background(from: average)
    }
}
