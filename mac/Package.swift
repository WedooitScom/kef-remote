// swift-tools-version: 6.0
// Client natif macOS pour les enceintes KEF (LS50 Wireless II, LSX II, LS60).
// - KEFKit   : protocole, client HTTP, démo, favoris, logique d'état (testable sans UI)
// - KEFRemote: application SwiftUI (fenêtre, barre des menus, MediaPlayer)
import PackageDescription

let package = Package(
    name: "KEFRemote",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KEFRemote", targets: ["KEFRemote"]),
        .library(name: "KEFKit", targets: ["KEFKit"]),
    ],
    targets: [
        // Chaînes traduites (fr, en, es, it, ja) : String Catalogs compilés par SwiftPM.
        .target(name: "KEFKit", resources: [.process("Localizable.xcstrings")]),
        .executableTarget(
            name: "KEFRemote",
            dependencies: ["KEFKit"],
            // Recopiés dans « KEF Remote.app/Contents/Resources/<langue>.lproj » par build-app.sh
            // (bundle principal : SwiftUI y cherche les Text("…") et AppKit ses menus standard).
            resources: [.process("Localizable.xcstrings"), .process("InfoPlist.xcstrings")]
        ),
        .testTarget(
            name: "KEFKitTests",
            dependencies: ["KEFKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
