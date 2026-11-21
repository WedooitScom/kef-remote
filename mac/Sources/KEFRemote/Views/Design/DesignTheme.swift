import AppKit
import KEFKit
import SwiftUI

// MARK: - Thème injecté

/// Couleurs et réglages communs à un design, injectés via l'environnement : les vues
/// partagées (recherche, lignes de station, favoris…) s'y adaptent sans connaître le design.
struct DesignTheme {
    var design: AppDesign
    /// Accent (teinte des contrôles, station en cours, focus).
    var accent: Color
    /// Étoile « favori ».
    var favorite: Color
    /// Fond et bordure du champ de recherche.
    var fieldFill: AnyShapeStyle
    var fieldStroke: Color
    var fieldCornerRadius: CGFloat
    /// Apparence imposée (`nil` = suit le système).
    var forcedScheme: ColorScheme?

    static let classique = DesignTheme(
        design: .classique, accent: .kefAccent, favorite: .yellow,
        fieldFill: AnyShapeStyle(.primary.opacity(0.06)), fieldStroke: .primary.opacity(0.06),
        fieldCornerRadius: 9, forcedScheme: nil
    )

    static let hifi = DesignTheme(
        design: .hifi, accent: HiFiPalette.amber, favorite: HiFiPalette.amber,
        fieldFill: AnyShapeStyle(HiFiPalette.display), fieldStroke: HiFiPalette.edge,
        fieldCornerRadius: 3, forcedScheme: .dark
    )

    static let immersif = DesignTheme(
        design: .immersif, accent: .white, favorite: .white,
        fieldFill: AnyShapeStyle(.white.opacity(0.08)), fieldStroke: .white.opacity(0.12),
        fieldCornerRadius: 12, forcedScheme: .dark
    )

    static let editorial = DesignTheme(
        design: .editorial, accent: EditorialPalette.orange, favorite: EditorialPalette.orange,
        fieldFill: AnyShapeStyle(Color.clear), fieldStroke: EditorialPalette.rule,
        fieldCornerRadius: 0, forcedScheme: nil
    )

    static let baladeur = DesignTheme(
        design: .baladeur, accent: BaladeurPalette.accent, favorite: .orange,
        fieldFill: AnyShapeStyle(Color.white.opacity(0.75)), fieldStroke: Color(hex: 0x8794A0),
        fieldCornerRadius: 3, forcedScheme: nil
    )

    static let pixel = DesignTheme(
        design: .pixel, accent: PixelPalette.Dynamic.accent, favorite: PixelPalette.Dynamic.favorite,
        fieldFill: AnyShapeStyle(PixelPalette.Dynamic.card), fieldStroke: PixelPalette.Dynamic.ink,
        fieldCornerRadius: 0, forcedScheme: nil
    )

    static let neon = DesignTheme(
        design: .neon, accent: NeonPalette.Dynamic.accent, favorite: NeonPalette.Dynamic.favorite,
        fieldFill: AnyShapeStyle(NeonPalette.Dynamic.field), fieldStroke: NeonPalette.Dynamic.fieldStroke,
        fieldCornerRadius: 8, forcedScheme: nil
    )

    static func of(_ design: AppDesign) -> DesignTheme {
        switch design {
        case .classique: .classique
        case .hifi: .hifi
        case .immersif: .immersif
        case .editorial: .editorial
        case .baladeur: .baladeur
        case .pixel: .pixel
        case .neon: .neon
        }
    }
}

extension EnvironmentValues {
    @Entry var designTheme: DesignTheme = .classique
}

// MARK: - Couleurs utilitaires

extension Color {
    /// `Color(hex: 0x1b1b1d)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    init(_ rgb: SRGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Couleur qui dépend de l'apparence (clair / sombre).
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension SpeakerSource {
    /// Libellé court façon façade d'appareil (WIFI, BT, OPT…).
    var panelLabel: String {
        switch self {
        case .wifi: "WIFI"
        case .bluetooth: "BT"
        case .tv: "TV"
        case .optic: "OPT"
        case .coaxial: "COAX"
        case .analog: "AUX"
        case .usb: "USB"
        }
    }
}

// MARK: - Sélection du design

/// Design affiché : `--design` (session, non mémorisé) sinon la préférence enregistrée.
@MainActor
enum DesignSelection {
    static func current(model: AppModel, stored raw: String) -> AppDesign {
        model.designOverride ?? AppDesign.stored(raw)
    }

    /// Liaison pour les réglages et le menu : choisir un design l'enregistre et annule
    /// l'éventuel `--design` de la ligne de commande. Changement animé.
    static func binding(model: AppModel, stored raw: Binding<String>) -> Binding<AppDesign> {
        Binding(
            get: { current(model: model, stored: raw.wrappedValue) },
            set: { design in
                withAnimation(.easeInOut(duration: 0.4)) {
                    model.designOverride = nil
                    raw.wrappedValue = design.rawValue
                }
            }
        )
    }
}

// MARK: - Tailles de fenêtre

/// Mise en page de la fenêtre principale : bande de la barre de titre, tailles minimales.
enum DesignLayout {
    /// Hauteur de la barre de titre (masquée mais toujours là, avec les feux de la fenêtre).
    /// Le contenu commence dessous, quelle que soit la façon dont SwiftUI calcule la zone
    /// de sécurité de la fenêtre ; seuls les fonds s'étendent dessous.
    static let titleBarHeight: CGFloat = 28

    /// Taille minimale (contenu + barre de titre) : chaque design s'adapte au-dessus
    /// (une ou deux colonnes, pochette qui rétrécit, défilement quand la hauteur manque).
    static func minimumSize(_ design: AppDesign) -> NSSize {
        switch design {
        case .classique: NSSize(width: 520, height: 540)
        case .hifi: NSSize(width: 660, height: 560)
        case .immersif: NSSize(width: 560, height: 540)
        case .editorial: NSSize(width: 520, height: 540)
        case .baladeur: NSSize(width: 420, height: 560)
        case .pixel: NSSize(width: 520, height: 660)
        case .neon: NSSize(width: 540, height: 640)
        }
    }
}

// MARK: - Racines

/// Contenu de la fenêtre principale selon le design choisi.
struct MainRoot: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppDesign.storageKey) private var designRaw = AppDesign.defaultDesign.rawValue

    var body: some View {
        let design = DesignSelection.current(model: model, stored: designRaw)
        let theme = DesignTheme.of(design)
        let minimum = DesignLayout.minimumSize(design)
        ZStack {
            switch design {
            case .classique:
                MainView().transition(.opacity)
            case .hifi:
                HiFiMainView().transition(.opacity)
            case .immersif:
                ImmersiveMainView().transition(.opacity)
            case .editorial:
                EditorialMainView().transition(.opacity)
            case .baladeur:
                BaladeurMainView().transition(.opacity)
            case .pixel:
                PixelMainView().transition(.opacity)
            case .neon:
                NeonMainView().transition(.opacity)
            }
            // Explorateur de radios (le Baladeur a son propre menu « Explorer »).
            if model.showsExplorer && design != .baladeur {
                RadioExplorerView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        // Les vues de design dessinent leur fond sous la barre de titre (`ignoresSafeArea`)
        // et placent leur contenu sous la bande réservée.
        .safeAreaPadding(.top, DesignLayout.titleBarHeight)
        .overlay(alignment: .bottom) { ToastView() }
        .overlay(alignment: .topTrailing) {
            // Sélecteur de design, discret, dans la barre de titre (à droite des feux).
            DesignMenuButton()
                .padding(.trailing, 10)
                .frame(height: DesignLayout.titleBarHeight)
        }
        .ignoresSafeArea(.container, edges: .top)
        // La hauteur minimale de la vue s'entend sous la barre de titre.
        .frame(minWidth: minimum.width, minHeight: minimum.height - DesignLayout.titleBarHeight)
        .animation(.easeInOut(duration: 0.4), value: design)
        .themed(theme)
    }
}

/// Menu des designs (icône palette, coche sur le design affiché) : barre de titre de la
/// fenêtre principale. Lisible sur les fonds clairs comme sombres de tous les designs.
struct DesignMenuButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppDesign.storageKey) private var designRaw = AppDesign.defaultDesign.rawValue
    var size: CGFloat = 12

    var body: some View {
        let selection = DesignSelection.binding(model: model, stored: $designRaw)
        Menu {
            Picker("Design", selection: selection) {
                ForEach(AppDesign.allCases) { design in
                    Text(design.label).tag(design)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
        .help("Design : \(selection.wrappedValue.label) (⌃⌘1 … ⌃⌘\(AppDesign.allCases.count))")
        .accessibilityLabel("Choisir le design")
        .accessibilityValue(selection.wrappedValue.label)
    }
}

/// Rangée de vignettes des designs (mini-lecteur) : un clic change de design.
struct DesignSwatches: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppDesign.storageKey) private var designRaw = AppDesign.defaultDesign.rawValue
    var width: CGFloat = 22

    var body: some View {
        let selection = DesignSelection.binding(model: model, stored: $designRaw)
        let ring = scheme == .dark ? Color.white : Color.black.opacity(0.75)
        HStack(spacing: 5) {
            ForEach(AppDesign.allCases) { design in
                let selected = design == selection.wrappedValue
                Button { selection.wrappedValue = design } label: {
                    DesignThumbnail(design: design)
                        .frame(width: width, height: width * 0.7)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(selected ? ring : ring.opacity(0.25), lineWidth: selected ? 1.5 : 0.5))
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(selected ? ring.opacity(0.35) : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Design \(design.label)")
                .accessibilityLabel("Design \(design.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.15), value: selection.wrappedValue)
    }
}

/// Contenu du mini-lecteur (barre des menus) selon le design choisi.
struct MiniPlayerRoot: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppDesign.storageKey) private var designRaw = AppDesign.defaultDesign.rawValue

    var body: some View {
        let design = DesignSelection.current(model: model, stored: designRaw)
        Group {
            switch design {
            case .classique: MiniPlayerView()
            case .hifi: HiFiMiniPlayer()
            case .immersif: ImmersiveMiniPlayer()
            case .editorial: EditorialMiniPlayer()
            case .baladeur: BaladeurMiniPlayer()
            case .pixel: PixelMiniPlayer()
            case .neon: NeonMiniPlayer()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.4), value: design)
        .themed(DesignTheme.of(design))
    }
}

extension View {
    /// Injecte le thème, la teinte et l'apparence imposée éventuelle.
    func themed(_ theme: DesignTheme) -> some View {
        modifier(ThemeModifier(theme: theme))
    }
}

private struct ThemeModifier: ViewModifier {
    let theme: DesignTheme
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content
            .environment(\.designTheme, theme)
            .tint(theme.accent)
            .environment(\.colorScheme, theme.forcedScheme ?? systemScheme)
    }
}

// MARK: - Vignettes d'aperçu (Réglages)

/// Choix du design par vignettes cliquables.
struct DesignPicker: View {
    @Binding var selection: AppDesign

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(AppDesign.allCases) { design in
                let selected = design == selection
                Button { selection = design } label: {
                    VStack(spacing: 6) {
                        DesignThumbnail(design: design)
                            .frame(height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(selected ? Color.kefAccent : .primary.opacity(0.15), lineWidth: selected ? 2.5 : 1)
                            )
                            .shadow(color: .black.opacity(selected ? 0.2 : 0.08), radius: selected ? 5 : 2, y: 1)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.kefAccent)
                            }
                            // Sept vignettes : les libellés longs passent sur deux lignes.
                            Text(design.label)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption.weight(selected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(design.summary)
                .accessibilityLabel("Design \(design.label)")
                .accessibilityHint(design.summary)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.2), value: selection)
        .padding(.vertical, 4)
    }
}

/// Aperçu dessiné de chaque design (couleurs fixes, indépendantes de l'apparence).
struct DesignThumbnail: View {
    let design: AppDesign

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            switch design {
            case .classique:
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(hex: 0xEDEBEA), Color(hex: 0xDCD7D3)], startPoint: .top, endPoint: .bottom)
                    RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(hex: 0xE87338), Color(hex: 0x7A3A1C)],
                                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: h * 0.46, height: h * 0.46).offset(x: w * 0.1, y: h * 0.12)
                    Circle().fill(Color.kefAccent).frame(width: h * 0.16).offset(x: w * 0.1 + h * 0.15, y: h * 0.7)
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.14))
                            .frame(width: w * 0.1, height: w * 0.1)
                            .offset(x: w * 0.5 + CGFloat(i % 3) * w * 0.14, y: h * 0.3 + CGFloat(i / 3) * w * 0.14)
                    }
                    Capsule().fill(Color.black.opacity(0.45)).frame(width: w * 0.3, height: 3).offset(x: w * 0.5, y: h * 0.14)
                }
            case .hifi:
                ZStack(alignment: .topLeading) {
                    HiFiPalette.background
                    RoundedRectangle(cornerRadius: 2).fill(HiFiPalette.display)
                        .frame(width: w * 0.5, height: h * 0.34).offset(x: w * 0.07, y: h * 0.14)
                    Capsule().fill(HiFiPalette.amber).frame(width: w * 0.3, height: 2.5).offset(x: w * 0.11, y: h * 0.24)
                    Capsule().fill(HiFiPalette.amber.opacity(0.5)).frame(width: w * 0.2, height: 2).offset(x: w * 0.11, y: h * 0.33)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0x2E2E31))
                            .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(i == 0 ? HiFiPalette.amber : .black.opacity(0.6), lineWidth: 1))
                            .frame(width: w * 0.085, height: h * 0.14)
                            .offset(x: w * 0.07 + CGFloat(i) * w * 0.105, y: h * 0.66)
                    }
                    Circle().fill(RadialGradient(colors: [Color(hex: 0x4A4A4E), Color(hex: 0x1E1E20)], center: .topLeading,
                                                 startRadius: 0, endRadius: h * 0.5))
                        .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
                        .frame(width: h * 0.56).offset(x: w * 0.66, y: h * 0.2)
                    Capsule().fill(HiFiPalette.amber).frame(width: 2, height: h * 0.12)
                        .offset(x: w * 0.66 + h * 0.27, y: h * 0.25)
                }
            case .immersif:
                ZStack(alignment: .top) {
                    // Pochette floutée plein cadre, colonne centrée, pastilles en bas.
                    DemoArtworkView(hue: 280, style: .immersif).scaleEffect(1.6).blur(radius: 8)
                    LinearGradient(colors: [.clear, Color(hex: 0x1C1028).opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    Capsule().fill(.white.opacity(0.16)).frame(width: w * 0.88, height: h * 0.09).offset(y: h * 0.05)
                    DemoArtworkView(hue: 280, style: .immersif).frame(width: h * 0.4, height: h * 0.4)
                        .clipShape(RoundedRectangle(cornerRadius: 3)).offset(y: h * 0.19)
                    Capsule().fill(.white).frame(width: w * 0.3, height: h * 0.06).offset(y: h * 0.63)
                    Circle().fill(.white).frame(width: h * 0.12).offset(y: h * 0.72)
                    HStack(spacing: w * 0.025) {
                        ForEach(0..<4, id: \.self) { i in
                            Capsule().fill(.white.opacity(i == 1 ? 0.95 : 0.28)).frame(width: w * 0.2, height: h * 0.08)
                        }
                    }
                    .offset(y: h * 0.88)
                }
                .clipped()
            case .baladeur:
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xF4F2EF), Color(hex: 0xCFCAC4)], startPoint: .top, endPoint: .bottom)
                    RoundedRectangle(cornerRadius: h * 0.1, style: .continuous)
                        .fill(LinearGradient(colors: [.white, Color(hex: 0xE2E2DE)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .frame(width: h * 0.56, height: h * 0.9)
                    VStack(spacing: 0) {
                        Rectangle().fill(Color(hex: 0xEEF1F4)).frame(height: h * 0.06)
                        Rectangle().fill(LinearGradient(colors: [Color(hex: 0x6DB4F6), Color(hex: 0x2770D8)],
                                                        startPoint: .top, endPoint: .bottom)).frame(height: h * 0.07)
                        Rectangle().fill(Color(hex: 0xC9D3DB))
                    }
                    .frame(width: h * 0.46, height: h * 0.32)
                    .overlay(Rectangle().strokeBorder(Color(hex: 0x111315), lineWidth: 1.5))
                    .offset(y: -h * 0.2)
                    Circle().fill(Color(hex: 0xF7F7F5))
                        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.75))
                        .frame(width: h * 0.34).offset(y: h * 0.19)
                    Circle().fill(Color(hex: 0xEAEAE6))
                        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                        .frame(width: h * 0.12).offset(y: h * 0.19)
                }
            case .pixel:
                PixelThumbnailArt()
            case .neon:
                NeonThumbnailArt()
            case .editorial:
                ZStack(alignment: .topLeading) {
                    Color(hex: 0xF4F1EA)
                    Rectangle().fill(Color(hex: 0x141414)).frame(width: w * 0.42, height: h * 0.11).offset(x: w * 0.07, y: h * 0.2)
                    Rectangle().fill(Color(hex: 0x141414)).frame(width: w * 0.3, height: h * 0.11).offset(x: w * 0.07, y: h * 0.36)
                    Rectangle().fill(Color(hex: 0x141414)).frame(width: h * 0.15, height: h * 0.15).offset(x: w * 0.07, y: h * 0.66)
                    Rectangle().fill(Color.black.opacity(0.25)).frame(width: 1, height: h).offset(x: w * 0.6)
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(i == 1 ? EditorialPalette.orange : Color(hex: 0x141414).opacity(0.55))
                            .frame(width: w * 0.24, height: 2.5).offset(x: w * 0.67, y: h * 0.2 + CGFloat(i) * h * 0.18)
                        Rectangle().fill(Color.black.opacity(0.15))
                            .frame(width: w * 0.3, height: 1).offset(x: w * 0.65, y: h * 0.29 + CGFloat(i) * h * 0.18)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
