import AppKit
import KEFKit
import SwiftUI

@main
struct KEFRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage(AppDesign.storageKey) private var designRaw = AppDesign.defaultDesign.rawValue

    var body: some Scene {
        Window("KEF Remote", id: "main") {
            MainRoot()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)
        .commands {
            PlayerCommands(model: model)
            DesignCommands(model: model, designRaw: $designRaw)
        }

        MenuBarExtra {
            MiniPlayerRoot()
                .environment(model)
        } label: {
            Image(systemName: model.store.snapshot.isPlaying ? "hifispeaker.fill" : "hifispeaker")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .tint(.kefAccent)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lancé hors bundle (`swift run`) : se comporter comme une app normale (Dock, menus).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Fermer la fenêtre ne quitte pas l'app : le mini-lecteur reste dans la barre des menus.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Menus « Commandes » et « Radios » avec raccourcis clavier.
/// (Espace = lecture/pause est géré par un moniteur clavier, cf. AppModel, pour ne pas
/// gêner la saisie dans les champs de texte.)
struct PlayerCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Commandes") {
            let store = model.store
            let next = model.skipPlan(.next), previous = model.skipPlan(.previous)
            Button(store.snapshot.isPlaying ? "Pause (Espace)" : "Lecture (Espace)") { Task { await store.playPause() } }
            // Radio : zapping dans les favoris ; ailleurs : pistes (si l'enceinte le permet).
            Button(next.label) { model.skip(.next) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!next.isEnabled)
            Button(previous.label) { model.skip(.previous) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!previous.isEnabled)
            Divider()
            Button("Augmenter le volume") { store.adjustVolume(by: 2) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Diminuer le volume") { store.adjustVolume(by: -2) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button(store.snapshot.isMuted ? "Rétablir le son" : "Couper le son") { store.toggleMute() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Button(store.snapshot.isOn ? "Mettre en veille" : "Allumer") { Task { await store.togglePower() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Menu("Source") {
                ForEach(store.snapshot.sources) { source in
                    Button(source.label) { Task { await store.selectSource(source) } }
                }
            }
        }
        CommandMenu("Radios") {
            if model.favorites.items.isEmpty {
                Text("Aucune radio favorite")
            }
            ForEach(Array(model.favorites.items.prefix(9).enumerated()), id: \.element.id) { index, station in
                Button(station.title) { model.playFavorite(at: index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("Ajouter la radio en cours aux favoris") { model.toggleCurrentFavorite() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model.store.snapshot.currentStation == nil)
            Button("Importer des favoris…") { model.importFavorites() }
            Divider()
            Button(model.showsExplorer ? "Fermer l'explorateur" : "Explorer les radios…") { model.toggleExplorer() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.currentDesign == .baladeur || !model.store.hasClient)
        }
    }
}

/// Menu « Présentation › Design » (⌃⌘1 … ⌃⌘7).
struct DesignCommands: Commands {
    let model: AppModel
    @Binding var designRaw: String

    var body: some Commands {
        // Design affiché (`--design` compris) : les coches suivent l'override de session.
        let current = DesignSelection.current(model: model, stored: designRaw)
        let selection = DesignSelection.binding(model: model, stored: $designRaw)
        CommandGroup(before: .toolbar) {
            Menu("Design") {
                ForEach(Array(AppDesign.allCases.enumerated()), id: \.element) { index, design in
                    Toggle(design.label, isOn: Binding(
                        get: { current == design },
                        set: { if $0 { selection.wrappedValue = design } }
                    ))
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .control])
                }
            }
            Divider()
        }
    }
}
