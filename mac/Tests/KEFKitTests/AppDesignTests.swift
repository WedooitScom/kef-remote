import CoreGraphics
import Foundation
import Testing
@testable import KEFKit

@Suite("Designs")
struct AppDesignTests {
    // MARK: Énumération

    @Test func rawValuesAreStable() {
        // Valeurs persistées dans UserDefaults : ne pas les renommer.
        #expect(AppDesign.allCases.map(\.rawValue) == ["classique", "hifi", "immersif", "editorial", "baladeur"])
        #expect(AppDesign.storageKey == "appDesign")
        #expect(AppDesign.defaultDesign == .classique)
    }

    @Test func parseIsTolerant() {
        #expect(AppDesign.parse("hifi") == .hifi)
        #expect(AppDesign.parse("Hi-Fi") == .hifi)
        #expect(AppDesign.parse(" HIFI ") == .hifi)
        #expect(AppDesign.parse("Éditorial") == .editorial)
        #expect(AppDesign.parse("editorial") == .editorial)
        #expect(AppDesign.parse("immersive") == .immersif)
        #expect(AppDesign.parse("classic") == .classique)
        #expect(AppDesign.parse("Baladeur") == .baladeur)
        #expect(AppDesign.parse("iPod") == .baladeur)
        #expect(AppDesign.parse("rétro") == .baladeur)
        #expect(AppDesign.parse("néon") == nil)
        #expect(AppDesign.parse("") == nil)
        #expect(AppDesign.parse(nil) == nil)
    }

    @Test func storedFallsBackToDefault() {
        #expect(AppDesign.stored(nil) == .classique)
        #expect(AppDesign.stored("inconnu") == .classique)
        #expect(AppDesign.stored("immersif") == .immersif)
        for design in AppDesign.allCases {
            #expect(AppDesign.stored(design.rawValue) == design)
        }
    }

    @Test func persistsThroughUserDefaults() throws {
        let suite = "kef-design-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppDesign.stored(defaults.string(forKey: AppDesign.storageKey)) == .classique)
        defaults.set(AppDesign.editorial.rawValue, forKey: AppDesign.storageKey)
        #expect(AppDesign.stored(defaults.string(forKey: AppDesign.storageKey)) == .editorial)
        defaults.set(AppDesign.baladeur.rawValue, forKey: AppDesign.storageKey)
        #expect(AppDesign.stored(defaults.string(forKey: AppDesign.storageKey)) == .baladeur)
    }

    @Test func labelsAreDistinct() {
        let labels = AppDesign.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        #expect(AppDesign.allCases.allSatisfy { !$0.summary.isEmpty })
    }

    // MARK: Molette cliquable

    @Test func clickWheelZones() {
        #expect(ClickWheelGeometry.zone(forAngle: 0) == .menu)
        #expect(ClickWheelGeometry.zone(forAngle: 90) == .next)
        #expect(ClickWheelGeometry.zone(forAngle: -90) == .previous)
        #expect(ClickWheelGeometry.zone(forAngle: 180) == .playPause)
        #expect(ClickWheelGeometry.zone(forAngle: -170) == .playPause)
        #expect(ClickWheelGeometry.zone(forAngle: 44) == .menu)
        #expect(ClickWheelGeometry.zone(forAngle: 270) == .previous)
    }

    @Test func clickWheelNotches() {
        #expect(ClickWheelGeometry.notches(in: 10).steps == 0)
        #expect(ClickWheelGeometry.notches(in: 40).steps == 2)
        #expect(ClickWheelGeometry.notches(in: 40).remainder == 4)
        #expect(ClickWheelGeometry.notches(in: -37).steps == -2)
    }

    @Test func clickWheelListWindow() {
        #expect(ClickWheelGeometry.window(selection: 0, count: 3, visible: 6) == 0..<3)
        #expect(ClickWheelGeometry.window(selection: 0, count: 20, visible: 6) == 0..<6)
        #expect(ClickWheelGeometry.window(selection: 10, count: 20, visible: 6) == 7..<13)
        #expect(ClickWheelGeometry.window(selection: 19, count: 20, visible: 6) == 14..<20)
        #expect(ClickWheelGeometry.window(selection: 5, count: 0, visible: 6).isEmpty)
    }

    // MARK: Molette

    @Test func knobValueToAngle() {
        #expect(KnobGeometry.angle(forValue: 0) == -135)
        #expect(KnobGeometry.angle(forValue: 50) == 0)
        #expect(KnobGeometry.angle(forValue: 100) == 135)
        #expect(KnobGeometry.angle(forValue: 25) == -67.5)
        // Bornes.
        #expect(KnobGeometry.angle(forValue: -10) == -135)
        #expect(KnobGeometry.angle(forValue: 150) == 135)
    }

    @Test func knobAngleToValue() {
        #expect(KnobGeometry.value(forAngle: -135) == 0)
        #expect(KnobGeometry.value(forAngle: 0) == 50)
        #expect(KnobGeometry.value(forAngle: 135) == 100)
        #expect(KnobGeometry.value(forAngle: 170) == 100)
        #expect(KnobGeometry.value(forAngle: -170) == 0)
        for v in stride(from: 0.0, through: 100, by: 7) {
            #expect(abs(KnobGeometry.value(forAngle: KnobGeometry.angle(forValue: v)) - v) < 1e-9)
        }
    }

    @Test func knobPointAngle() {
        let c = CGPoint(x: 100, y: 100)
        #expect(abs(KnobGeometry.angle(of: CGPoint(x: 100, y: 0), around: c)) < 1e-9)       // haut
        #expect(abs(KnobGeometry.angle(of: CGPoint(x: 200, y: 100), around: c) - 90) < 1e-9) // droite
        #expect(abs(KnobGeometry.angle(of: CGPoint(x: 0, y: 100), around: c) + 90) < 1e-9)   // gauche
        #expect(abs(abs(KnobGeometry.angle(of: CGPoint(x: 100, y: 200), around: c)) - 180) < 1e-9) // bas
    }

    @Test func knobDeltaWrapsAround() {
        #expect(KnobGeometry.delta(from: 10, to: 30) == 20)
        #expect(KnobGeometry.delta(from: 170, to: -170) == 20)
        #expect(KnobGeometry.delta(from: -170, to: 170) == -20)
        #expect(KnobGeometry.valueDelta(forRotation: 27) == 10)
        #expect(KnobGeometry.valueDelta(forRotation: -270) == -100)
    }

    // MARK: Couleur dominante

    /// Image synthétique : moitié gauche `left`, moitié droite `right`.
    private func image(width: Int = 40, height: Int = 20, left: SRGBColor, right: SRGBColor) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: left.red, green: left.green, blue: left.blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(red: right.red, green: right.green, blue: right.blue, alpha: 1)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(ctx.makeImage())
    }

    @Test func averageOfSolidColor() throws {
        let red = SRGBColor(red: 1, green: 0, blue: 0)
        let avg = try #require(DominantColor.average(of: try image(left: red, right: red)))
        #expect(abs(avg.red - 1) < 0.02)
        #expect(avg.green < 0.02)
        #expect(avg.blue < 0.02)
    }

    @Test func averageOfTwoHalves() throws {
        let avg = try #require(DominantColor.average(of: try image(left: SRGBColor(red: 1, green: 0, blue: 0),
                                                                   right: SRGBColor(red: 0, green: 0, blue: 1))))
        #expect(abs(avg.red - 0.5) < 0.03)
        #expect(avg.green < 0.03)
        #expect(abs(avg.blue - 0.5) < 0.03)
    }

    @Test func backgroundKeepsHueAndContrast() throws {
        let orange = SRGBColor(red: 0.95, green: 0.55, blue: 0.1)
        let bg = DominantColor.backgroundColor(for: try image(left: orange, right: orange))
        #expect(bg.contrastRatio(with: .white) >= 7)
        // Toujours orangé (rouge > vert > bleu), mais sombre.
        #expect(bg.red > bg.green && bg.green > bg.blue)
        #expect(bg.hsb.brightness <= 0.42)
        #expect(abs(bg.hsb.hue - orange.hsb.hue) < 0.03)
    }

    @Test func backgroundOfBrightColorsIsReadable() {
        for c in [SRGBColor.white, SRGBColor(red: 1, green: 1, blue: 0), SRGBColor(red: 0, green: 1, blue: 1),
                  SRGBColor(red: 0.6, green: 1, blue: 0.4)] {
            #expect(DominantColor.background(from: c).contrastRatio(with: .white) >= 7)
        }
    }

    @Test func fallbackWithoutImage() {
        #expect(DominantColor.backgroundColor(for: nil) == DominantColor.fallback)
        #expect(DominantColor.fallback.contrastRatio(with: .white) >= 7)
    }

    @Test func hsbRoundTrip() {
        for c in [SRGBColor(red: 0.2, green: 0.4, blue: 0.8), SRGBColor(red: 0.9, green: 0.1, blue: 0.3),
                  SRGBColor(red: 0.5, green: 0.5, blue: 0.5)] {
            let (h, s, b) = c.hsb
            let back = SRGBColor(hue: h, saturation: s, brightness: b)
            #expect(abs(back.red - c.red) < 1e-9 && abs(back.green - c.green) < 1e-9 && abs(back.blue - c.blue) < 1e-9)
        }
    }
}
