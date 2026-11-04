import KEFKit
import SwiftUI

/// Réglages (⌘,) : présentation, adresse de l'enceinte, découverte Bonjour, favoris.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppDesign.storageKey) private var designRaw = AppDesign.defaultDesign.rawValue
    @State private var hostInput = ""
    @State private var probeResult: String?
    @State private var probeOK = false
    @State private var probing = false

    var body: some View {
        Form {
            Section {
                DesignPicker(selection: DesignSelection.binding(model: model, stored: $designRaw))
            } header: {
                Text("Design")
            } footer: {
                Text("S'applique à la fenêtre et au mini-lecteur. Aussi dans le menu Présentation › Design (⌃⌘1 à ⌃⌘5).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Enceinte") {
                if model.isDemo {
                    Label("Mode démo actif : l'enceinte est simulée (lancé avec --demo ou KEF_DEMO=1).", systemImage: "theatermasks")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Adresse IP", text: $hostInput, prompt: Text("192.168.1.20"))
                        .onSubmit(save)
                    Button("Tester", action: probe).disabled(hostInput.isEmpty || probing)
                    Button("Connecter", action: save).keyboardShortcut(.defaultAction).disabled(hostInput.isEmpty)
                }
                if probing {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Test en cours…").foregroundStyle(.secondary) }
                } else if let probeResult {
                    Label(probeResult, systemImage: probeOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(probeOK ? .green : .orange)
                }
                LabeledContent("État") {
                    HStack(spacing: 6) {
                        StatusDot(status: model.store.status)
                        Text(model.store.status.label).lineLimit(1)
                    }
                }
                if let fw = model.store.snapshot.firmware {
                    LabeledContent("Modèle", value: [model.store.snapshot.modelLabel, fw].compactMap { $0 }.joined(separator: " · "))
                }
            }

            Section {
                if model.discovery.speakers.filter(\.isKEF).isEmpty {
                    HStack(spacing: 8) {
                        if model.discovery.isBrowsing { ProgressView().controlSize(.small) }
                        Text(model.discovery.error ?? (model.discovery.isBrowsing ? "Recherche des enceintes KEF…" : "Aucune recherche en cours"))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.discovery.kefSpeakers) { speaker in
                    HStack {
                        Image(systemName: "hifispeaker.fill").foregroundStyle(Color.kefAccent)
                        VStack(alignment: .leading) {
                            Text(speaker.name)
                            Text([speaker.model, speaker.host ?? "résolution…"].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Utiliser") {
                            guard let host = speaker.host else { return }
                            hostInput = host
                            save()
                        }
                        .disabled(speaker.host == nil || speaker.host == model.host)
                    }
                }
            } header: {
                HStack {
                    Text("Enceintes détectées (Bonjour)")
                    Spacer()
                    Button("Rechercher") { model.discovery.start() }.controlSize(.small)
                }
            } footer: {
                Text("Au premier lancement, macOS demande l'autorisation d'accéder au réseau local : elle est nécessaire pour piloter l'enceinte.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Radios favorites") {
                LabeledContent("Fichier") {
                    Text(model.favorites.fileURL.path(percentEncoded: false))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                LabeledContent("Stations", value: "\(model.favorites.items.count)")
                HStack {
                    Button("Importer…") { model.importFavorites() }
                    Button("Afficher dans le Finder") { model.revealFavoritesFile() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 560)
        .onAppear {
            hostInput = model.host ?? ""
            if !model.isDemo { model.discovery.start() }
        }
        .onDisappear { model.discovery.stop() }
    }

    private func save() {
        do {
            try model.setHost(hostInput)
            hostInput = model.host ?? hostInput
            probeResult = nil
        } catch {
            probeOK = false
            probeResult = describe(error)
        }
    }

    private func probe() {
        guard let host = try? HostValidator.normalize(hostInput) else {
            probeOK = false
            probeResult = describe(KEFError.invalidHost(hostInput))
            return
        }
        probing = true
        Task {
            defer { probing = false }
            do {
                let result = try await KEFHTTPClient.probe(host: host)
                let model = KEFParser.modelLabels[KEFParser.normalizeModel(KEFParser.splitRelease(result.release).model)]
                probeOK = true
                probeResult = "\(result.name) — \(model ?? result.release)"
            } catch {
                probeOK = false
                probeResult = "Pas de réponse KEF : \(describe(error))"
            }
        }
    }
}
