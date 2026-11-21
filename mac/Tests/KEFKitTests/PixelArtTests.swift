import CoreGraphics
import Foundation
import Testing
@testable import KEFKit

@Suite("Rétro pixel")
struct PixelArtTests {
    // MARK: Police bitmap

    @Test func coversCapitalsDigitsAndFrenchAccents() {
        let required = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;!?'\"-_/()+&%#*·…«»@€°"
            + "ÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒÆ⏻★♪"
        for ch in required {
            #expect(PixelFont.covers(ch), "glyphe manquant : \(ch)")
            let glyph = PixelFont.glyph(for: ch)
            #expect(glyph.rows.count == PixelFont.cellHeight)
            if ch != " " { #expect(glyph.litCount > 0, "glyphe vide : \(ch)") }
        }
    }

    @Test func glyphsAreAtMostFiveColumnsWideAndSevenRowsTall() {
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            let g = PixelFont.glyph(for: ch)
            #expect(g.width <= 5)
            // Rien dans les lignes d'accents ni de jambage pour les capitales simples.
            for row in 0..<PixelFont.capTop { #expect(g.rows[row] == 0) }
            #expect(g.rows[PixelFont.capTop + PixelFont.capHeight] == 0)
        }
        // Les chiffres ont tous la même largeur (afficheurs alignés).
        #expect(Set("0123456789".map { PixelFont.glyph(for: $0).width }).count == 1)
    }

    @Test func accentsSitAboveTheLetterAndCedillaBelow() {
        let e = PixelFont.glyph(for: "E"), eAcute = PixelFont.glyph(for: "É")
        for row in PixelFont.capTop..<(PixelFont.capTop + PixelFont.capHeight) { #expect(e.rows[row] == eAcute.rows[row]) }
        #expect(eAcute.rows[0] != 0 || eAcute.rows[1] != 0)
        #expect(PixelFont.glyph(for: "É") != PixelFont.glyph(for: "È"))
        let cedilla = PixelFont.glyph(for: "Ç")
        #expect(cedilla.rows[PixelFont.capTop + PixelFont.capHeight] != 0)
    }

    @Test func lowercaseIsDrawnInCapitals() {
        #expect(PixelFont.normalize("été à l’œil") == "ÉTÉ À L'ŒIL")
        #expect(PixelFont.width(of: "radio") == PixelFont.width(of: "RADIO"))
        #expect(PixelFont.width(of: "ça") == PixelFont.width(of: "ÇA"))
    }

    @Test func coversSpanishAndItalianLetters() {
        for ch in "ÑÁÉÍÓÚÜÀÈÌÒÙ¿¡ÃÕ–—‹›" {
            #expect(PixelFont.covers(ch), "glyphe manquant : \(ch)")
            let glyph = PixelFont.glyph(for: ch)
            #expect(glyph.rows.count == PixelFont.cellHeight)
            #expect(glyph.litCount > 0, "glyphe vide : \(ch)")
        }
        // Tilde au-dessus du N, capitale intacte ; ¿ est un ? retourné.
        let n = PixelFont.glyph(for: "N"), eñe = PixelFont.glyph(for: "Ñ")
        #expect(eñe != n)
        for row in PixelFont.capTop..<(PixelFont.capTop + PixelFont.capHeight) { #expect(eñe.rows[row] == n.rows[row]) }
        // ¿ : le ? tourné d'un demi-tour (point en haut).
        let question = PixelFont.glyph(for: "?"), inverted = PixelFont.glyph(for: "¿")
        for y in 0..<PixelFont.capHeight {
            for x in 0..<question.width {
                #expect(inverted.isOn(x: x, y: PixelFont.capTop + y)
                    == question.isOn(x: question.width - 1 - x, y: PixelFont.capTop + PixelFont.capHeight - 1 - y))
            }
        }
        #expect(PixelFont.normalize("¿qué pasó? ¡sì!") == "¿QUÉ PASÓ? ¡SÌ!")
    }

    @Test func japaneseUsesTheSystemFontRasterized() {
        for ch in "スタンバイ再生音量設定ラジオ、ー" {
            #expect(PixelFont.usesSystemFont(ch), "\(ch)")
            #expect(!PixelFont.covers(ch))
            let glyph = PixelFont.glyph(for: ch)
            #expect(glyph != PixelFont.fallback, "damier pour \(ch)")
            #expect(glyph.rows.count == PixelFont.cellHeight)
            #expect(glyph.litCount > 0)
            #expect(glyph.width >= 3 && glyph.width <= PixelFont.cellHeight)
        }
        // Deux caractères différents, deux glyphes différents ; même caractère, même glyphe (cache).
        #expect(PixelFont.glyph(for: "再") != PixelFont.glyph(for: "生"))
        #expect(PixelFont.glyph(for: "再") == PixelFont.glyph(for: "再"))
        // Mise en page mixte latin / japonais, ponctuation pleine chasse ramenée à l'ASCII.
        #expect(PixelFont.normalize("リビング（デモ）：kef") == "リビング(デモ):KEF")
        #expect(PixelFont.width(of: "ラジオ") > PixelFont.width(of: "AB"))
        #expect(PixelFont.truncate("お気に入りのラジオ局をすべて表示", toWidth: 40).hasSuffix("…"))
    }

    @Test func unknownCharactersFallBack() {
        // Lettre accentuée sans glyphe dédié : lettre de base.
        #expect(!PixelFont.covers("Å"))
        #expect(PixelFont.glyph(for: "Å") == PixelFont.glyph(for: "A"))
        #expect(PixelFont.glyph(for: "Ŕ") == PixelFont.glyph(for: "R"))
        // Sans équivalent : damier, jamais vide.
        for ch: Character in ["🎵", "Ж", "א"] {
            #expect(PixelFont.glyph(for: ch) == PixelFont.fallback)
        }
        #expect(PixelFont.fallback.litCount > 0)
        #expect(PixelFont.glyph(for: "\t") == PixelFont.glyph(for: " "))
    }

    @Test func textWidth() {
        #expect(PixelFont.width(of: "") == 0)
        #expect(PixelFont.width(of: "A") == 5)
        #expect(PixelFont.width(of: "AB") == 11)          // 5 + 1 + 5
        #expect(PixelFont.width(of: "I") == 3)            // glyphe étroit
        #expect(PixelFont.width(of: "WIFI") == 5 + 1 + 3 + 1 + 5 + 1 + 3)
        let layout = PixelFont.layout("KEF")
        #expect(layout.map(\.x) == [0, 6, 12])
        #expect(PixelFont.width(of: "KEF") == layout.last!.x + layout.last!.glyph.width)
    }

    @Test func truncateFitsTheWidth() {
        let long = "Radio Cuivre Groove"
        let cut = PixelFont.truncate(long, toWidth: 40)
        #expect(PixelFont.width(of: cut) <= 40)
        #expect(cut.hasSuffix("…"))
        #expect(PixelFont.truncate("KEF", toWidth: 40) == "KEF")
    }

    // MARK: Échelle entière

    @Test func integerScaleFits() {
        let logical = CGSize(width: 184, height: 128)
        #expect(PixelScale.fit(logical, in: CGSize(width: 552, height: 384)) == 3)   // pile
        #expect(PixelScale.fit(logical, in: CGSize(width: 551, height: 1000)) == 2)  // un point de moins
        #expect(PixelScale.fit(logical, in: CGSize(width: 2000, height: 520)) == 4)  // la hauteur limite
        #expect(PixelScale.fit(logical, in: CGSize(width: 100, height: 100), range: 2...5) == 2) // minimum imposé
        #expect(PixelScale.fit(logical, in: CGSize(width: 5000, height: 5000), range: 2...5) == 5) // maximum
        for w in stride(from: 200, through: 1400, by: 37) {
            let k = PixelScale.fit(logical, in: CGSize(width: w, height: 900), range: 1...8)
            #expect(CGFloat(k) * logical.width <= CGFloat(w))
            #expect(CGFloat(k + 1) * logical.width > CGFloat(w) || k == 8)
        }
    }

    @Test func centeringAndSnappingStayOnWholePoints() {
        #expect(PixelScale.centered(552, in: 600) == 24)
        #expect(PixelScale.centered(552, in: 601) == 24)    // arrondi vers le bas, jamais de demi-point
        #expect(PixelScale.centered(700, in: 600) == 0)
        #expect(PixelScale.snap(10.3, backing: 2) == 10.5)
        #expect(PixelScale.snap(10.2, backing: 1) == 10)
    }

    @Test func pixelRectGeometry() {
        let r = PixelRect(2, 3, 10, 6)
        #expect(r.maxX == 12 && r.maxY == 9)
        #expect(r.inset(1) == PixelRect(3, 4, 8, 4))
        #expect(r.cgRect(scale: 3) == CGRect(x: 6, y: 9, width: 30, height: 18))
        #expect(r.intersects(PixelRect(11, 8, 4, 4)))
        #expect(!r.intersects(PixelRect(12, 3, 4, 4)))   // bord commun : pas de chevauchement
        #expect(r.contains(PixelRect(3, 4, 2, 2)))
    }

    @Test func discIsSymmetric() {
        for d in [4, 6, 11, 12, 28, 46] {
            let spans = PixelArt.discSpans(diameter: d)
            #expect(spans.count == d)
            for (i, span) in spans.enumerated() {
                let mirror = spans[d - 1 - i]
                #expect(span == mirror)
                #expect(span.lowerBound >= 0 && span.upperBound <= d)
                #expect(span.lowerBound + span.upperBound == d) // centré horizontalement
            }
            #expect(spans[d / 2].count == d) // ligne médiane pleine
        }
    }

    // MARK: Défilement

    @Test func marqueeOffsets() {
        #expect(PixelMarquee.offset(textWidth: 40, boxWidth: 50, time: 3) == 0)   // tient : immobile
        #expect(PixelMarquee.offset(textWidth: 100, boxWidth: 50, time: 0) == 0)  // pause au début
        #expect(PixelMarquee.offset(textWidth: 100, boxWidth: 50, time: 1.5, pause: 1.6) == 0)
        #expect(PixelMarquee.offset(textWidth: 100, boxWidth: 50, time: 2.6, speed: 10, pause: 1.6) == 10)
        let cycle = 100 + PixelMarquee.gap
        for t in stride(from: 0.0, through: 30, by: 0.37) {
            let o = PixelMarquee.offset(textWidth: 100, boxWidth: 50, time: t)
            #expect(o >= 0 && o < cycle)
        }
    }

    // MARK: Poste

    @Test func boomboxPartsStayInsideAndApart() {
        for layout in [BoomboxLayout.regular, .compactLayout] {
            #expect(layout.size.contains(layout.body))
            #expect(layout.size.contains(layout.body.offset(2, 2)) || layout.body.offset(2, 2).maxY <= layout.size.maxY + 2)
            for part in layout.frontParts { #expect(layout.body.contains(part), "\(part) déborde") }
            #expect(layout.dial.contains(layout.band) && layout.dial.contains(layout.scale))
            #expect(!layout.band.intersects(layout.scale))
            #expect(!layout.speakers[0].intersects(layout.cassetteWindow))
            #expect(!layout.speakers[1].intersects(layout.cassetteWindow))
            #expect(layout.cassetteWindow.contains(layout.cassette))
            #expect(layout.reelWindow.contains(layout.cover))
            for reel in layout.reels { #expect(layout.reelWindow.contains(reel) && !reel.intersects(layout.cover)) }
            if let label = layout.label { #expect(layout.cassette.contains(label) && !label.intersects(layout.reelWindow)) }
            #expect(layout.pianoKeys.count == 4)
            for (a, b) in zip(layout.pianoKeys, layout.pianoKeys.dropFirst()) { #expect(!a.intersects(b) && a.maxX < b.x + 1) }
            for key in layout.topKeys { #expect(!key.intersects(layout.handle) && layout.size.contains(key)) }
            // Haut-parleurs ronds, de diamètre pair (disques concentriques centrés).
            for s in layout.speakers { #expect(s.w == s.h && s.w % 2 == 0) }
            #expect(layout.antennaTip.x < layout.size.maxX && layout.antennaTip.y >= 0)
        }
        #expect(BoomboxLayout.regular.label != nil && !BoomboxLayout.regular.compact)
        #expect(BoomboxLayout.compactLayout.compact)
        #expect(BoomboxLayout.regular.topKeys.count == 3 && BoomboxLayout.compactLayout.topKeys.count == 2)
    }

    @Test func dialNeedleFollowsVolume() {
        let l = BoomboxLayout.regular
        #expect(l.needleX(volume: 0) == l.scale.x)
        #expect(l.needleX(volume: 100) == l.scale.maxX - 1)
        #expect(l.needleX(volume: -5) == l.scale.x && l.needleX(volume: 140) == l.scale.maxX - 1)
        var last = -1
        for v in 0...100 {
            let x = l.needleX(volume: v)
            #expect(x >= last)
            last = x
            #expect(abs(l.volume(atX: Double(x)) - v) <= 1)
        }
        #expect(l.antennaLength(on: true) > l.antennaLength(on: false))
    }

    // MARK: Pochette réduite

    @Test func downsampleKeepsHalvesAndPosterizes() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 40))   // moitié gauche rouge
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 20, y: 0, width: 20, height: 40))  // moitié droite bleue
        let image = try #require(ctx.makeImage())
        let px = try #require(PixelArt.downsample(image, side: 4))
        #expect(px.count == 16)
        #expect(px[0] == SRGBColor(red: 1, green: 0, blue: 0))
        #expect(px[3] == SRGBColor(red: 0, green: 0, blue: 1))
        // Posterisation : composantes sur 6 niveaux.
        for c in px { for v in [c.red, c.green, c.blue] { #expect(abs(v * 5 - (v * 5).rounded()) < 1e-9) } }
    }
}

@Suite("Palette années 80 et pochettes de repli")
struct ArtworkTests {
    @Test func tilePairsStayInThePaletteAndAreReadable() {
        for pair in Synthwave.pairs {
            #expect(Synthwave.all.contains(pair.start) && Synthwave.all.contains(pair.end))
            // Titre blanc en bas à gauche, sur la fin (sombre) du dégradé.
            #expect(pair.end.contrastRatio(with: .white) >= 4.5, "\(pair)")
        }
    }

    @Test func genrePairsAreStableAndVaried() {
        let genres = ["Jazz", "Rock", "Pop", "Musique classique", "Actualités", "Electronic Dance", "Reggae", "Sport"]
        for g in genres { #expect(Synthwave.genrePair(for: g) == Synthwave.genrePair(for: g)) }
        #expect(Set(genres.map { Synthwave.genrePair(for: $0) }).count >= 5)
        #expect(Synthwave.genrePair(for: "JAZZ") == Synthwave.genrePair(for: "jazz"))
        #expect(Set((0..<3).map(Synthwave.entryPair)).count == 3)
    }

    @Test func scenesAreStableAndBounded() {
        for seed in [0, 24, 200, 280, 9999] {
            let a = Synthwave.scene(seed: seed), b = Synthwave.scene(seed: seed)
            #expect(a == b)
            #expect((0.25...0.76).contains(a.sunX))
            #expect((0.56...0.69).contains(a.horizon))
        }
        #expect(Set((0..<40).map { Synthwave.scene(seed: $0).sunX }).count > 5)
    }

    @Test func fallbackDiffersByStyleAndIsStable() {
        let seed = FallbackArtwork.seed(for: "Radio Cuivre")
        #expect(seed == FallbackArtwork.seed(for: "radio cuivre"))          // casse ignorée
        #expect(seed != FallbackArtwork.seed(for: "Kent Info"))
        let specs = ArtworkStyle.allCases.map { FallbackArtwork.spec(style: $0, seed: seed, title: "Radio Cuivre") }
        // Une variante par style : couleurs différentes d'un style à l'autre.
        #expect(Set(specs.map(\.colors)).count == ArtworkStyle.allCases.count)
        for style in ArtworkStyle.allCases {
            let a = FallbackArtwork.spec(style: style, seed: seed, title: "Radio Cuivre")
            #expect(a == FallbackArtwork.spec(style: style, seed: seed, title: "Radio Cuivre"))
            #expect(a.initial == "R")
            #expect((0..<3).contains(a.variant) && (0...1).contains(a.phase))
        }
        // Chaque design a son style ; le style « néon 80 » est prévu pour un futur design.
        #expect(Set(AppDesign.allCases.map(ArtworkStyle.init)).count == AppDesign.allCases.count)
        #expect(ArtworkStyle.allCases.contains(.neon80))
        #expect(FallbackArtwork.initial(of: "« Zénith »") == "Z")
        #expect(FallbackArtwork.initial(of: nil) == nil)
    }
}
