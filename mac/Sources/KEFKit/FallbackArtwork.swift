import Foundation

/// Style de la pochette de repli (station sans logo, piste sans pochette, démo). Un style
/// par design ; `neon80` (scène synthwave) est celui du design « Néon 80 ».
public enum ArtworkStyle: String, CaseIterable, Sendable {
    case classique, hifi, immersif, editorial, baladeur, pixel, neon80

    public init(_ design: AppDesign) {
        switch design {
        case .classique: self = .classique
        case .hifi: self = .hifi
        case .immersif: self = .immersif
        case .editorial: self = .editorial
        case .baladeur: self = .baladeur
        case .pixel: self = .pixel
        case .neon: self = .neon80
        }
    }
}

/// Paramètres d'une pochette de repli : tout se déduit de la graine (nom de station ou
/// teinte de démo), donc une station garde toujours la même pochette dans un design donné.
public struct FallbackArtworkSpec: Equatable, Sendable {
    public var style: ArtworkStyle
    public var seed: UInt32
    /// Motif (0…2) : cercles / bandes / arcs, vinyle / VU-mètre, filet en haut / en bas…
    public var variant: Int
    /// Couleurs du style (fond, motif, accent), dans l'ordre propre à chaque dessin.
    public var colors: [SRGBColor]
    /// Initiale de la station (monogramme), si un titre est connu.
    public var initial: Character?
    /// Valeur continue 0…1 tirée de la graine (angle d'aiguille, position d'un motif…).
    public var phase: Double
}

public enum FallbackArtwork {
    /// Graine stable d'un nom (casse et accents ignorés).
    public static func seed(for key: String) -> UInt32 {
        Synthwave.hash(RadioCatalog.fold(key))
    }

    /// Première lettre ou chiffre d'un titre, en capitale.
    public static func initial(of title: String?) -> Character? {
        guard let title else { return nil }
        return title.uppercased().first { $0.isLetter || $0.isNumber }
    }

    // Palettes par style (hexadécimal sRGB).
    static let classiquePairs: [(UInt32, UInt32)] = [
        (0xFF5F6D, 0xFFC371), (0x4776E6, 0x8E54E9), (0x11998E, 0x38EF7D),
        (0xF7797D, 0xC471ED), (0x2193B0, 0x6DD5ED), (0xFF8008, 0xFFC837),
    ]
    static let hifiColors: [UInt32] = [0x121214, 0xE8A03A, 0x2A2A2D, 0xDAD4CA]
    static let editorialAccents: [UInt32] = [0xD9481C, 0x141414, 0x1F4E79]
    static let baladeurAccents: [UInt32] = [0x2770D8, 0x8E99A6, 0x3AA35B]
    static let pixelPastels: [UInt32] = [0xF2A7B5, 0x7ED3C8, 0xEDC15B, 0x9DB0D8, 0xC5B3E6, 0xA8DDA0]

    public static func spec(style: ArtworkStyle, seed: UInt32, title: String? = nil) -> FallbackArtworkSpec {
        var h = seed &* 2_654_435_761 ^ 0x85EB_CA6B
        func next(_ n: UInt32) -> Int {
            h ^= h << 13
            h ^= h >> 17
            h ^= h << 5
            return Int(h % n)
        }
        let variant = next(3)
        let phase = Double(next(1000)) / 999
        let colors: [SRGBColor]
        switch style {
        case .classique:
            let pair = classiquePairs[next(UInt32(classiquePairs.count))]
            colors = [SRGBColor(hex: pair.0), SRGBColor(hex: pair.1), .white]
        case .hifi:
            colors = hifiColors.map(SRGBColor.init(hex:))
        case .immersif:
            // Trois teintes voisines, douces, sur un fond sombre de la même famille.
            // Teintes franches (cyan → bleu → violet → rose → rouge) : pas de kaki ni de brun.
            let hue = (0.5 + Double(next(56)) / 100).truncatingRemainder(dividingBy: 1)
            colors = [SRGBColor(hue: hue, saturation: 0.55, brightness: 0.22),
                      SRGBColor(hue: hue, saturation: 0.6, brightness: 0.9),
                      SRGBColor(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.95),
                      SRGBColor(hue: (hue + 0.82).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.8)]
        case .editorial:
            colors = [SRGBColor(hex: 0xF4F1EA), SRGBColor(hex: 0x141414),
                      SRGBColor(hex: editorialAccents[next(UInt32(editorialAccents.count))])]
        case .baladeur:
            colors = [SRGBColor(hex: 0xF4F6F8), SRGBColor(hex: 0xC4CCD5),
                      SRGBColor(hex: baladeurAccents[next(UInt32(baladeurAccents.count))])]
        case .pixel:
            colors = [SRGBColor(hex: pixelPastels[next(UInt32(pixelPastels.count))]), SRGBColor(hex: 0x2A2238),
                      SRGBColor(hex: 0xFFF7E4)]
        case .neon80:
            let sky = Synthwave.scene(seed: Int(seed)).sky
            colors = [sky.top, sky.horizon, sky.grid]
        }
        return FallbackArtworkSpec(style: style, seed: seed, variant: variant, colors: colors,
                                   initial: initial(of: title), phase: phase)
    }
}
