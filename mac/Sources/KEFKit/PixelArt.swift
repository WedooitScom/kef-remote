import CoreGraphics
import Foundation

// Design « Rétro pixel » : tout ce qui se teste sans interface — police bitmap, icônes,
// mise à l'échelle entière, défilement façon afficheur LED, géométrie du radio-cassette,
// réduction d'une pochette en quelques pixels.

// MARK: - Rectangle de pixels logiques

/// Rectangle sur la grille des pixels logiques (entiers, y vers le bas).
public struct PixelRect: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int

    public init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var maxX: Int { x + w }
    public var maxY: Int { y + h }
    public var midX: Int { x + w / 2 }
    public var midY: Int { y + h / 2 }

    /// Rectangle rétréci de `d` pixels de chaque côté.
    public func inset(_ d: Int) -> PixelRect { PixelRect(x + d, y + d, max(0, w - 2 * d), max(0, h - 2 * d)) }

    public func offset(_ dx: Int, _ dy: Int) -> PixelRect { PixelRect(x + dx, y + dy, w, h) }

    public func intersects(_ other: PixelRect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    public func contains(_ other: PixelRect) -> Bool {
        other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY
    }

    /// Rectangle en points pour un pixel logique de `scale` points.
    public func cgRect(scale: CGFloat) -> CGRect {
        CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: CGFloat(w) * scale, height: CGFloat(h) * scale)
    }
}

// MARK: - Police bitmap 5×7

/// Glyphe bitmap : `rows[r]` décrit la ligne `r` (bit de poids fort = colonne 0).
/// Cellule de `PixelFont.cellHeight` lignes : 2 pour les accents, 7 pour les capitales,
/// 1 de jambage (cédille, virgule).
public struct PixelGlyph: Equatable, Sendable {
    public let width: Int
    public let rows: [UInt8]

    public func isOn(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, rows.indices.contains(y) else { return false }
        return rows[y] & (1 << UInt8(width - 1 - x)) != 0
    }

    /// Nombre de pixels allumés (tests : un glyphe visible n'est pas vide).
    public var litCount: Int { rows.reduce(0) { $0 + $1.nonzeroBitCount } }

    /// Construit un glyphe à partir de lignes « #.#.. » (capitales) et d'éventuels accents.
    init(cap: [String], accent: [String] = [], descender: String? = nil) {
        let width = cap.map(\.count).max() ?? 0
        func bits(_ line: String) -> UInt8 {
            var value: UInt8 = 0
            for (i, ch) in line.enumerated() where ch == "#" && i < width {
                value |= 1 << UInt8(width - 1 - i)
            }
            return value
        }
        var rows = [UInt8](repeating: 0, count: PixelFont.cellHeight)
        let top = PixelFont.capTop - accent.count
        for (i, line) in accent.enumerated() { rows[top + i] = bits(line) }
        for (i, line) in cap.prefix(PixelFont.capHeight).enumerated() { rows[PixelFont.capTop + i] = bits(line) }
        if let descender { rows[PixelFont.capTop + PixelFont.capHeight] = bits(descender) }
        self.width = width
        self.rows = rows
    }
}

/// Police bitmap 5×7 dessinée en code : capitales, chiffres, ponctuation courante et
/// accents du français. Les minuscules s'affichent en capitales ; un caractère inconnu
/// est d'abord ramené à sa lettre de base (Ñ → N), sinon remplacé par un damier.
public enum PixelFont {
    /// Lignes réservées aux accents au-dessus des capitales.
    public static let capTop = 2
    public static let capHeight = 7
    /// Accents + capitales + jambage.
    public static let cellHeight = 10
    /// Espace entre deux glyphes (pixels logiques).
    public static let spacing = 1

    /// Glyphe d'un caractère déjà en capitales (repli compris).
    public static func glyph(for character: Character) -> PixelGlyph {
        if let g = table[character] { return g }
        if character.isWhitespace { return table[" "]! }
        // Lettre accentuée absente : lettre de base (Ñ → N, Å → A).
        let folded = String(character).folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .uppercased()
        if folded.count == 1, let base = folded.first, let g = table[base] { return g }
        return fallback
    }

    /// Le caractère a-t-il un glyphe dédié (sans repli) ?
    public static func covers(_ character: Character) -> Bool { table[character] != nil }

    /// Texte tel qu'il sera dessiné (capitales, « ß » → « SS »…).
    public static func normalize(_ text: String) -> String {
        text.uppercased(with: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2026}", with: "…")
    }

    /// Largeur du texte en pixels logiques (espacement compris, sans espace final).
    public static func width(of text: String) -> Int {
        let glyphs = normalize(text).map(glyph(for:))
        guard !glyphs.isEmpty else { return 0 }
        return glyphs.reduce(0) { $0 + $1.width } + spacing * (glyphs.count - 1)
    }

    /// Position horizontale de chaque glyphe (dessin, tests).
    public static func layout(_ text: String) -> [(x: Int, glyph: PixelGlyph)] {
        var x = 0
        var result: [(x: Int, glyph: PixelGlyph)] = []
        for ch in normalize(text) {
            let g = glyph(for: ch)
            result.append((x, g))
            x += g.width + spacing
        }
        return result
    }

    /// Coupe le texte pour qu'il tienne dans `maxWidth` pixels, avec « … » si besoin.
    public static func truncate(_ text: String, toWidth maxWidth: Int) -> String {
        let normalized = normalize(text)
        guard width(of: normalized) > maxWidth else { return normalized }
        var chars = Array(normalized)
        while !chars.isEmpty && width(of: String(chars) + "…") > maxWidth { chars.removeLast() }
        while chars.last == " " { chars.removeLast() }
        return chars.isEmpty ? "" : String(chars) + "…"
    }

    /// Damier : caractère sans glyphe (emoji, idéogramme…).
    public static let fallback = PixelGlyph(cap: ["#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#"])

    // MARK: Tables

    private static let accents: [String: [String]] = [
        "aigu": ["...#.", "..#.."],
        "grave": [".#...", "..#.."],
        "circ": ["..#..", ".#.#."],
        "trema": [".#.#.", "....."],
        "aigu3": ["..#", ".#."],
        "grave3": ["#..", ".#."],
        "circ3": [".#.", "#.#"],
        "trema3": ["#.#", "..."],
    ]

    private static let caps: [Character: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
        "J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "Œ": [".####", "#.#..", "#.#..", "#.###", "#.#..", "#.#..", ".####"],
        "Æ": [".####", "#.#..", "#.#..", "#####", "#.#..", "#.#..", "#.###"],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        " ": ["...", "...", "...", "...", "...", "...", "..."],
        ".": [".", ".", ".", ".", ".", ".", "#"],
        ":": [".", ".", "#", ".", ".", "#", "."],
        "!": ["#", "#", "#", "#", "#", ".", "#"],
        "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
        "'": ["#", "#", ".", ".", ".", ".", "."],
        "\"": ["#.#", "#.#", "...", "...", "...", "...", "..."],
        "-": ["....", "....", "....", "####", "....", "....", "...."],
        "_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
        "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
        "(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
        ")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
        "[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
        "]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
        "=": ["....", "....", "####", "....", "####", "....", "...."],
        "<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
        ">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
        "&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
        "%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
        "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
        "*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
        "@": [".###.", "#...#", "#.###", "#.#.#", "#.###", "#....", ".####"],
        "|": ["#", "#", "#", "#", "#", "#", "#"],
        "·": [".", ".", ".", "#", ".", ".", "."],
        "…": [".....", ".....", ".....", ".....", ".....", ".....", "#.#.#"],
        "°": [".#.", "#.#", ".#.", "...", "...", "...", "..."],
        "«": [".....", ".....", "..#.#", ".#.#.", "#.#..", ".#.#.", "..#.#"],
        "»": [".....", ".....", "#.#..", ".#.#.", "..#.#", ".#.#.", "#.#.."],
        "€": ["..###", ".#...", "####.", ".#...", "####.", ".#...", "..###"],
        "$": ["..#..", ".####", "#.#..", ".###.", "..#.#", "####.", "..#.."],
        "⏻": ["..#..", "#.#.#", "#.#.#", "#...#", "#...#", "#...#", ".###."],
        "★": ["..#..", "..#..", "#####", ".###.", ".###.", "##.##", "#...#"],
        "♪": ["..##.", "..#.#", "..#..", "..#..", ".##..", "###..", ".#..."],
    ]

    /// Lettres accentuées : lettre de base + accent (au-dessus) ou cédille (dessous).
    private static let accented: [Character: (base: Character, accent: String)] = [
        "À": ("A", "grave"), "Â": ("A", "circ"), "Ä": ("A", "trema"), "Á": ("A", "aigu"),
        "É": ("E", "aigu"), "È": ("E", "grave"), "Ê": ("E", "circ"), "Ë": ("E", "trema"),
        "Î": ("I", "circ3"), "Ï": ("I", "trema3"), "Í": ("I", "aigu3"), "Ì": ("I", "grave3"),
        "Ô": ("O", "circ"), "Ö": ("O", "trema"), "Ó": ("O", "aigu"), "Ò": ("O", "grave"),
        "Ù": ("U", "grave"), "Û": ("U", "circ"), "Ü": ("U", "trema"), "Ú": ("U", "aigu"),
        "Ÿ": ("Y", "trema"),
    ]

    private static let table: [Character: PixelGlyph] = {
        var t: [Character: PixelGlyph] = [:]
        for (ch, rows) in caps { t[ch] = PixelGlyph(cap: rows) }
        for (ch, spec) in accented {
            guard let rows = caps[spec.base], let accent = accents[spec.accent] else { continue }
            t[ch] = PixelGlyph(cap: rows, accent: accent)
        }
        t["Ç"] = PixelGlyph(cap: caps["C"]!, descender: "..#..")
        t[","] = PixelGlyph(cap: ["..", "..", "..", "..", "..", ".#", ".#"], descender: "#.")
        t[";"] = PixelGlyph(cap: ["..", "..", ".#", "..", "..", ".#", ".#"], descender: "#.")
        return t
    }()
}

// MARK: - Icônes

/// Petites icônes bitmap : « # » = encre (contour), « o » = remplissage, « . » = vide.
public struct PixelIcon: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Lignes de l'icône (`#`, `o`, `.`).
    public let rows: [String]

    public init(_ rows: [String]) {
        self.rows = rows
        width = rows.map(\.count).max() ?? 0
        height = rows.count
    }

    public enum Ink: Sendable { case ink, fill, none }

    public func ink(x: Int, y: Int) -> Ink {
        guard rows.indices.contains(y) else { return .none }
        let line = Array(rows[y])
        guard line.indices.contains(x) else { return .none }
        switch line[x] {
        case "#": return .ink
        case "o": return .fill
        default: return .none
        }
    }

    public static let play = PixelIcon(["#....", "##...", "###..", "####.", "###..", "##...", "#...."])
    public static let pause = PixelIcon(["##.##", "##.##", "##.##", "##.##", "##.##", "##.##", "##.##"])
    public static let stop = PixelIcon(["#####", "#####", "#####", "#####", "#####"])
    public static let previous = PixelIcon(["#...#..#", "#..##.##", "#.######", "#..##.##", "#...#..#"])
    public static let next = PixelIcon(["#..#...#", "##.##..#", "######.#", "##.##..#", "#..#...#"])
    public static let power = PixelIcon(["...#...", ".#.#.#.", "#..#..#", "#.....#", "#.....#", ".#...#.", "..###.."])
    public static let mute = PixelIcon(["..#....", "###.#.#", "###..#.", "###.#.#", "..#...."])
    public static let speaker = PixelIcon(["..#....", "###..#.", "###.#.#", "###..#.", "..#...."])
    public static let star = PixelIcon(["....#....", "...#o#...", "####o####", "#ooooooo#", ".#ooooo#.",
                                        "..#ooo#..", ".#oo#oo#.", ".#o#.#o#.", ".##...##."])
    public static let smallStar = PixelIcon(["..#..", ".###.", "#####", ".###.", ".#.#."])
    public static let globe = PixelIcon(["..###..", ".#o#o#.", "#oo#oo#", "#######", "#oo#oo#", ".#o#o#.", "..###.."])
    public static let gear = PixelIcon(["..#.#..", ".#####.", "##ooo##", ".#o.o#.", "##ooo##", ".#####.", "..#.#.."])
    public static let search = PixelIcon([".###...", "#ooo#..", "#ooo#..", "#ooo#..", ".####..", "....##.", ".....##"])
    public static let window = PixelIcon(["#######", "#ooooo#", "#######", "#.....#", "#.....#", "#######"])
    public static let menu = PixelIcon(["##.##.##", "##.##.##"])
    // Variantes réduites (touches du mini-lecteur).
    public static let previousSmall = PixelIcon(["#...#", "#..##", "#.###", "#..##", "#...#"])
    public static let nextSmall = PixelIcon(["#...#", "##..#", "###.#", "##..#", "#...#"])
    public static let playSmall = PixelIcon(["#..", "##.", "###", "##.", "#.."])
    public static let pauseSmall = PixelIcon(["#.#", "#.#", "#.#", "#.#", "#.#"])
    public static let powerSmall = PixelIcon(["..#..", "#.#.#", "#.#.#", "#...#", ".###."])
    public static let note = PixelIcon(["...###", "...#.#", "...#.#", ".###.#", "####.#", ".##.##", "....##"])
}

// MARK: - Échelle entière

/// Mise à l'échelle par multiples entiers du pixel logique : un pixel logique occupe
/// exactement `k` points (donc `k × 2` pixels physiques sur Retina), sans interpolation.
public enum PixelScale {
    /// Plus grand facteur entier `k` tel que `logical × k` tienne dans `available`,
    /// borné à `range` (le minimum s'applique même si la place manque).
    public static func fit(_ logical: CGSize, in available: CGSize, range: ClosedRange<Int> = 1...8) -> Int {
        guard logical.width > 0, logical.height > 0 else { return range.lowerBound }
        let kx = available.width / logical.width
        let ky = available.height / logical.height
        let k = Int(floor(min(kx, ky) + 1e-9))
        return min(max(k, range.lowerBound), range.upperBound)
    }

    /// Origine (points entiers) qui centre `content` dans `available`.
    public static func centered(_ content: CGFloat, in available: CGFloat) -> CGFloat {
        floor(max(0, available - content) / 2)
    }

    /// Valeur arrondie au pixel physique le plus proche (`backing` = pixels par point).
    public static func snap(_ value: CGFloat, backing: CGFloat = 2) -> CGFloat {
        guard backing > 0 else { return value }
        return (value * backing).rounded() / backing
    }
}

// MARK: - Défilement façon afficheur LED

public enum PixelMarquee {
    /// Écart (pixels logiques) entre la fin du texte et sa répétition.
    public static let gap = 14

    /// Décalage entier (pixels logiques, ≥ 0) d'un texte de `textWidth` dans une fenêtre de
    /// `boxWidth` à l'instant `time` : 0 si le texte tient ; sinon pause de `pause` secondes,
    /// puis défilement à `speed` px/s sur un cycle de `textWidth + gap` (le texte est
    /// redessiné à `cycle` pour boucler sans saut).
    public static func offset(textWidth: Int, boxWidth: Int, time: Double, speed: Double = 14, pause: Double = 1.6) -> Int {
        guard textWidth > boxWidth, speed > 0 else { return 0 }
        let cycle = textWidth + gap
        let period = pause + Double(cycle) / speed
        var phase = time.truncatingRemainder(dividingBy: period)
        if phase < 0 { phase += period }
        guard phase >= pause else { return 0 }
        return min(cycle - 1, Int((phase - pause) * speed))
    }

    /// Le texte défile-t-il ?
    public static func scrolls(textWidth: Int, boxWidth: Int) -> Bool { textWidth > boxWidth }
}

// MARK: - Dessin de base

public enum PixelArt {
    /// Disque de diamètre `d` sur la grille : colonnes allumées pour chaque ligne (symétrique).
    public static func discSpans(diameter d: Int) -> [Range<Int>] {
        guard d > 0 else { return [] }
        let r = Double(d) / 2
        return (0..<d).map { row in
            let dy = Double(row) + 0.5 - r
            let half = (r * r - dy * dy).squareRoot()
            let start = Int((r - half).rounded())
            let end = Int((r + half).rounded())
            return start..<max(start, end)
        }
    }

    /// Pochette réduite à `side × side` pixels (moyenne par zone), ligne par ligne depuis
    /// le haut, posterisée sur `levels` niveaux par composante (aspect pixel art).
    /// Les zones transparentes prennent la couleur `matte`.
    public static func downsample(_ image: CGImage, side: Int, levels: Int = 6,
                                  matte: SRGBColor = .white) -> [SRGBColor]? {
        guard side > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(red: matte.red, green: matte.green, blue: matte.blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.interpolationQuality = .high
        // Recadrage carré centré (pochettes et logos ne sont pas toujours carrés).
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let s = min(w, h)
        let target = CGRect(x: -(w - s) / 2 * CGFloat(side) / s, y: -(h - s) / 2 * CGFloat(side) / s,
                            width: w * CGFloat(side) / s, height: h * CGFloat(side) / s)
        ctx.draw(image, in: target)
        guard let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let steps = Double(max(2, levels) - 1)
        func level(_ v: UInt8) -> Double { (Double(v) / 255 * steps).rounded() / steps }
        var result: [SRGBColor] = []
        result.reserveCapacity(side * side)
        // Le contexte bitmap a son origine en haut à gauche en mémoire (ligne 0 = haut).
        for row in 0..<side {
            for col in 0..<side {
                let i = (row * side + col) * 4
                result.append(SRGBColor(red: level(bytes[i]), green: level(bytes[i + 1]), blue: level(bytes[i + 2])))
            }
        }
        return result
    }
}

// MARK: - Géométrie du radio-cassette

/// Emplacement des éléments du poste sur la grille logique. Deux variantes : fenêtre
/// (titre et artiste dans la cassette) et mini-lecteur (sans texte dans la cassette).
public struct BoomboxLayout: Sendable {
    public var size: PixelRect
    public var body: PixelRect
    public var handle: PixelRect
    /// Pied de l'antenne (sur le dessus du poste) et extrémité déployée.
    public var antennaBase: PixelRect
    public var antennaTip: (x: Int, y: Int)
    public var antennaRetractedLength: Int
    public var topKeys: [PixelRect]
    public var dial: PixelRect
    /// Zone de la bande (WIFI, BT…) à gauche du cadran.
    public var band: PixelRect
    /// Graduation du cadran : l'aiguille s'y déplace.
    public var scale: PixelRect
    public var speakers: [PixelRect]
    public var cassetteWindow: PixelRect
    public var cassette: PixelRect
    /// Étiquette de la cassette (titre / artiste) ; vide dans la variante compacte.
    public var label: PixelRect?
    /// Fenêtre des bobines (sous l'étiquette).
    public var reelWindow: PixelRect
    public var reels: [PixelRect]
    public var cover: PixelRect
    public var pianoKeys: [PixelRect]
    public var badge: PixelRect
    public var meter: PixelRect

    public var compact: Bool { label == nil }

    /// Tous les éléments posés sur la façade (tests : rien ne déborde, rien ne se chevauche).
    public var frontParts: [PixelRect] {
        [dial] + speakers + [cassetteWindow] + pianoKeys + [badge, meter]
    }

    /// Fenêtre principale : 184 × 128 pixels logiques.
    public static let regular = BoomboxLayout(
        size: PixelRect(0, 0, 184, 128),
        body: PixelRect(2, 24, 178, 100),
        handle: PixelRect(50, 6, 82, 20),
        antennaBase: PixelRect(146, 20, 10, 5),
        antennaTip: (180, 1),
        antennaRetractedLength: 5,
        topKeys: [PixelRect(8, 16, 12, 9), PixelRect(21, 16, 12, 9), PixelRect(34, 16, 12, 9)],
        dial: PixelRect(10, 31, 162, 16),
        band: PixelRect(12, 33, 29, 12),
        scale: PixelRect(45, 33, 124, 12),
        speakers: [PixelRect(9, 52, 46, 46), PixelRect(127, 52, 46, 46)],
        cassetteWindow: PixelRect(58, 50, 66, 54),
        cassette: PixelRect(61, 53, 60, 49),
        label: PixelRect(64, 56, 54, 24),
        reelWindow: PixelRect(64, 82, 54, 16),
        reels: [PixelRect(67, 84, 12, 12), PixelRect(103, 84, 12, 12)],
        cover: PixelRect(84, 83, 14, 14),
        pianoKeys: [PixelRect(58, 106, 15, 14), PixelRect(75, 106, 15, 14), PixelRect(92, 106, 15, 14), PixelRect(109, 106, 15, 14)],
        badge: PixelRect(12, 104, 40, 14),
        meter: PixelRect(130, 108, 40, 8)
    )

    /// Mini-lecteur : 110 × 82 pixels logiques.
    public static let compactLayout = BoomboxLayout(
        size: PixelRect(0, 0, 110, 82),
        body: PixelRect(1, 17, 106, 62),
        handle: PixelRect(32, 4, 44, 15),
        antennaBase: PixelRect(86, 13, 8, 5),
        antennaTip: (108, 0),
        antennaRetractedLength: 4,
        topKeys: [PixelRect(6, 10, 11, 8), PixelRect(19, 10, 11, 8)],
        dial: PixelRect(6, 22, 96, 11),
        band: PixelRect(8, 24, 23, 7),
        scale: PixelRect(34, 24, 66, 7),
        speakers: [PixelRect(5, 36, 28, 28), PixelRect(75, 36, 28, 28)],
        cassetteWindow: PixelRect(36, 36, 36, 28),
        cassette: PixelRect(38, 38, 32, 24),
        label: nil,
        reelWindow: PixelRect(40, 44, 28, 12),
        reels: [PixelRect(41, 46, 8, 8), PixelRect(59, 46, 8, 8)],
        cover: PixelRect(49, 45, 10, 10),
        pianoKeys: [PixelRect(36, 66, 8, 10), PixelRect(45, 66, 9, 10), PixelRect(55, 66, 8, 10), PixelRect(64, 66, 8, 10)],
        badge: PixelRect(6, 67, 26, 9),
        meter: PixelRect(77, 69, 24, 5)
    )

    /// Abscisse de l'aiguille pour un volume 0…100 (bornée à la graduation).
    public func needleX(volume: Int) -> Int {
        let v = min(max(volume, 0), 100)
        return scale.x + Int((Double(v) / 100 * Double(scale.w - 1)).rounded())
    }

    /// Volume 0…100 correspondant à une abscisse (pixels logiques, fraction comprise).
    public func volume(atX x: Double) -> Int {
        let t = (x - Double(scale.x)) / Double(max(1, scale.w - 1))
        return Int((min(max(t, 0), 1) * 100).rounded())
    }

    /// Longueur visible de l'antenne : déployée si l'enceinte est allumée.
    public func antennaLength(on: Bool) -> Int {
        on ? max(abs(antennaTip.x - antennaBase.midX), abs(antennaTip.y - antennaBase.y)) : antennaRetractedLength
    }
}
