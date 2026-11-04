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
        .target(name: "KEFKit"),
        .executableTarget(
            name: "KEFRemote",
            dependencies: ["KEFKit"]
        ),
        .testTarget(
            name: "KEFKitTests",
            dependencies: ["KEFKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
