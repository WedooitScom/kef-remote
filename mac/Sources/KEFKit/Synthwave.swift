import Foundation

/// Palette « années 80 » de l'explorateur de radios et des pochettes de repli : couchers
/// de soleil rose → orange → violet, néons cyan et magenta, nuit indigo. Tout est
/// déterministe : un même nom donne toujours les mêmes couleurs.
public enum Synthwave {
    // MARK: Couleurs

    public static let hotPink = SRGBColor(hex: 0xFF2E88)
    public static let magenta = SRGBColor(hex: 0xFF3CAC)
    public static let orange = SRGBColor(hex: 0xFF8A3D)
    public static let sun = SRGBColor(hex: 0xFFC861)
    public static let cyan = SRGBColor(hex: 0x22E4F2)
    public static let turquoise = SRGBColor(hex: 0x00C2B8)
    public static let violet = SRGBColor(hex: 0x7B2FF7)
    public static let night = SRGBColor(hex: 0x1B0F3A)
    public static let indigo = SRGBColor(hex: 0x2B1055)
    // Teintes sombres de la même famille (fin de dégradé sous un texte blanc).
    public static let deepMagenta = SRGBColor(hex: 0xB0166E)
    public static let plum = SRGBColor(hex: 0x5A189A)
    public static let deepTeal = SRGBColor(hex: 0x0B6E7A)

    /// Toutes les couleurs de la palette (tests : rien d'autre n'est utilisé).
    public static let all: [SRGBColor] = [hotPink, magenta, orange, sun, cyan, turquoise, violet, night, indigo,
                                          deepMagenta, plum, deepTeal]

    // MARK: Dégradés

    /// Dégradé de deux couleurs : `start` lumineux (en haut à gauche), `end` assez sombre
    /// pour un texte blanc (en bas, là où est le titre).
    public struct Pair: Equatable, Hashable, Sendable {
        public var start: SRGBColor
        public var end: SRGBColor

        public init(_ start: SRGBColor, _ end: SRGBColor) {
            self.start = start
            self.end = end
        }
    }

    /// Dégradés des tuiles (genres, langues, étagères), dans un ordre qui alterne chaud / froid.
    public static let pairs: [Pair] = [
        Pair(hotPink, violet),
        Pair(cyan, plum),
        Pair(orange, deepMagenta),
        Pair(magenta, indigo),
        Pair(turquoise, plum),
        Pair(sun, deepMagenta),
        Pair(violet, night),
        Pair(cyan, deepTeal),
        Pair(orange, plum),
        Pair(hotPink, indigo),
    ]

    /// Dégradé stable d'après un nom (langue, étagère…).
    public static func pair(forKey key: String) -> Pair {
        pairs[Int(hash(RadioCatalog.fold(key)) % UInt32(pairs.count))]
    }

    /// Dégradé d'un genre : les genres reconnus suivent l'ordre des règles (voisins
    /// différents), les autres une valeur dérivée du nom.
    public static func genrePair(for name: String) -> Pair {
        if let index = RadioCatalog.genreRuleIndex(for: name) { return pairs[(index * 3) % pairs.count] }
        return pair(forKey: name)
    }

    // MARK: Ciels

    /// Ciel de coucher de soleil (haut → horizon) et sol nocturne.
    public struct Sky: Equatable, Sendable {
        public var top: SRGBColor
        public var middle: SRGBColor
        public var horizon: SRGBColor
        public var ground: SRGBColor
        public var grid: SRGBColor
        public var sunTop: SRGBColor
        public var sunBottom: SRGBColor
    }

    public static let skies: [Sky] = [
        Sky(top: indigo, middle: violet, horizon: hotPink, ground: night, grid: magenta, sunTop: sun, sunBottom: hotPink),
        Sky(top: night, middle: plum, horizon: orange, ground: night, grid: cyan, sunTop: sun, sunBottom: magenta),
        Sky(top: violet, middle: magenta, horizon: sun, ground: indigo, grid: cyan, sunTop: sun, sunBottom: orange),
        Sky(top: night, middle: deepTeal, horizon: turquoise, ground: night, grid: magenta, sunTop: sun, sunBottom: hotPink),
        Sky(top: plum, middle: hotPink, horizon: orange, ground: night, grid: magenta, sunTop: sun, sunBottom: hotPink),
        Sky(top: night, middle: indigo, horizon: magenta, ground: night, grid: cyan, sunTop: orange, sunBottom: magenta),
    ]

    /// Paramètres d'une petite scène (pochette de repli, tuiles d'accueil).
    public struct Scene: Equatable, Sendable {
        public var sky: Sky
        /// Centre du soleil (fraction de la largeur, 0,25…0,75).
        public var sunX: Double
        /// Diamètre du soleil (fraction du côté).
        public var sunSize: Double
        /// Ligne d'horizon (fraction de la hauteur depuis le haut, 0,56…0,68).
        public var horizon: Double
        /// Palmiers : aucun, à gauche, à droite ou des deux côtés.
        public var palms: Palms

        public enum Palms: Sendable, Equatable { case none, left, right, both }
    }

    /// Scène stable pour une graine (teinte de démo, nom de station…).
    public static func scene(seed: Int) -> Scene {
        var h = UInt32(truncatingIfNeeded: seed) &* 2_654_435_761 ^ 0x9E37_79B9
        func next(_ n: UInt32) -> UInt32 {
            h ^= h << 13
            h ^= h >> 17
            h ^= h << 5
            return h % n
        }
        let sky = skies[Int(next(UInt32(skies.count)))]
        let sunX = 0.25 + Double(next(51)) / 100
        let sunSize = 0.42 + Double(next(15)) / 100
        let horizon = 0.56 + Double(next(13)) / 100
        let palms: Scene.Palms = [.none, .left, .right, .both, .right][Int(next(5))]
        return Scene(sky: sky, sunX: sunX, sunSize: sunSize, horizon: horizon, palms: palms)
    }

    /// Scènes des trois entrées de l'accueil (Pays, Genres, Langues) : ciels et soleils
    /// différents, sans palmiers (le titre est posé dessus).
    public static func entryScene(_ index: Int) -> Scene {
        let presets: [Scene] = [
            Scene(sky: skies[0], sunX: 0.76, sunSize: 0.6, horizon: 0.5, palms: .none),
            Scene(sky: skies[2], sunX: 0.72, sunSize: 0.68, horizon: 0.52, palms: .none),
            Scene(sky: skies[3], sunX: 0.78, sunSize: 0.56, horizon: 0.48, palms: .none),
        ]
        return presets[((index % presets.count) + presets.count) % presets.count]
    }

    /// Dégradés des trois entrées de l'accueil (distincts).
    public static func entryPair(_ index: Int) -> Pair {
        let presets = [pairs[0], pairs[2], pairs[1]]
        return presets[((index % presets.count) + presets.count) % presets.count]
    }

    /// Scène d'une station sans pochette (graine tirée du nom).
    public static func scene(forKey key: String) -> Scene {
        scene(seed: Int(hash(RadioCatalog.fold(key))))
    }

    static func hash(_ s: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}

extension SRGBColor {
    /// `SRGBColor(hex: 0xFF2E88)`
    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension RadioCatalog {
    /// Rang de la règle de genre reconnue (`nil` si le genre n'est pas reconnu).
    public static func genreRuleIndex(for name: String) -> Int? {
        let key = fold(name)
        return genreRules.firstIndex { $0.keywords.contains(where: { key.contains($0) }) }
    }
}
