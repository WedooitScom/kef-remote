import Foundation
import Network
import Observation
import os

/// Enceinte repérée sur le réseau local.
public struct DiscoveredSpeaker: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var host: String?
    public var model: String?
    public var isKEF: Bool
    public var services: Set<String>
}

/// Règles de reconnaissance des enceintes KEF dans les annonces Bonjour.
///
/// Relevé sur une LS50 Wireless II : `_airplay._tcp` annonce `manufacturer=KEF`
/// et `model=LS50 Wireless II` ; `_raop._tcp` s'appelle `MAC@LS50 Wireless II-xxxx`
/// (TXT `am=LS50 Wireless II`) ; `_googlecast._tcp` porte le nom convivial dans `fn` ;
/// `_http._tcp` (port 80, l'API) porte le nom de l'enceinte. Pas de service « KEF » dédié.
public enum KEFDiscoveryFilter {
    public static let serviceTypes = ["_airplay._tcp", "_raop._tcp", "_googlecast._tcp", "_http._tcp"]
    static let hints = ["kef", "ls50", "lsx", "ls60"]

    public static func isKEF(name: String, txt: [String: String]) -> Bool {
        if txt["manufacturer"]?.lowercased() == "kef" { return true }
        let blob = [name, txt["model"], txt["md"], txt["am"], txt["fn"]].compactMap { $0 }.joined(separator: " ").lowercased()
        return hints.contains { blob.contains($0) }
    }

    /// Nom affichable : `fn` (Chromecast), sinon le nom du service sans le préfixe RAOP « MAC@ ».
    public static func friendlyName(serviceName: String, txt: [String: String]) -> String {
        if let fn = txt["fn"], !fn.isEmpty { return fn }
        if let at = serviceName.firstIndex(of: "@") { return String(serviceName[serviceName.index(after: at)...]) }
        return serviceName
    }

    public static func model(txt: [String: String]) -> String? {
        for key in ["model", "am", "md"] {
            // Chromecast met des chiffres dans `md` ; RAOP met « 0,1,2 » : on écarte ces valeurs.
            if let v = txt[key], v.rangeOfCharacter(from: .letters) != nil { return v }
        }
        return nil
    }
}

/// Découverte Bonjour (NWBrowser) des enceintes KEF, avec résolution de l'IPv4.
@MainActor
@Observable
public final class SpeakerDiscovery {
    public private(set) var speakers: [DiscoveredSpeaker] = []
    public private(set) var isBrowsing = false
    public private(set) var error: String?

    private var browsers: [NWBrowser] = []
    private var resolving: Set<String> = []
    private let queue = DispatchQueue(label: "fr.wedooit.kefremote.discovery")
    private static let log = Logger(subsystem: "fr.wedooit.kefremote", category: "discovery")

    public init() {}

    /// Enceintes KEF uniquement, triées par nom.
    public var kefSpeakers: [DiscoveredSpeaker] { speakers.filter(\.isKEF) }

    public func start() {
        stop()
        error = nil
        isBrowsing = true
        for type in KEFDiscoveryFilter.serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: params)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap(Self.describe)
                Task { @MainActor in self?.ingest(found, type: type) }
            }
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed(let err) = state {
                    let message = "Découverte impossible : \(err.localizedDescription)"
                    Task { @MainActor in self?.error = message }
                } else if case .waiting(let err) = state {
                    // Typiquement : autorisation « réseau local » refusée ou en attente.
                    let message = "Découverte en attente : \(err.localizedDescription)"
                    Task { @MainActor in self?.error = message }
                }
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
    }

    public func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        isBrowsing = false
    }

    /// Résultat Bonjour réduit à des valeurs `Sendable`.
    struct Found: Sendable {
        let name: String
        let txt: [String: String]
        let endpoint: NWEndpoint
    }

    nonisolated static func describe(_ result: NWBrowser.Result) -> Found? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        var txt: [String: String] = [:]
        if case .bonjour(let record) = result.metadata {
            for (key, entry) in record {
                if case .string(let value) = entry { txt[key.lowercased()] = value }
            }
        }
        return Found(name: name, txt: txt, endpoint: result.endpoint)
    }

    private func ingest(_ found: [Found], type: String) {
        let service = type.split(separator: ".").first.map { String($0.dropFirst()) } ?? type
        for item in found {
            let name = KEFDiscoveryFilter.friendlyName(serviceName: item.name, txt: item.txt)
            let kef = KEFDiscoveryFilter.isKEF(name: item.name, txt: item.txt)
            if let i = speakers.firstIndex(where: { $0.name == name }) {
                speakers[i].isKEF = speakers[i].isKEF || kef
                speakers[i].services.insert(service)
                if speakers[i].model == nil { speakers[i].model = KEFDiscoveryFilter.model(txt: item.txt) }
            } else {
                speakers.append(DiscoveredSpeaker(name: name, host: nil, model: KEFDiscoveryFilter.model(txt: item.txt),
                                                  isKEF: kef, services: [service]))
            }
            if let i = speakers.firstIndex(where: { $0.name == name }), speakers[i].isKEF,
               speakers[i].host == nil, !resolving.contains(name) {
                resolving.insert(name)
                resolve(item.endpoint, name: name)
            }
        }
        speakers.sort { ($0.isKEF ? 0 : 1, $0.name.lowercased()) < ($1.isKEF ? 0 : 1, $1.name.lowercased()) }
    }

    /// Résout l'IPv4 d'un service en ouvrant (puis fermant) une connexion TCP.
    private func resolve(_ endpoint: NWEndpoint, name: String) {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { [weak self, connection] state in
            switch state {
            case .ready:
                let host = Self.ipv4(from: connection.currentPath?.remoteEndpoint)
                connection.cancel()
                Task { @MainActor in self?.resolved(name: name, host: host) }
            case .failed, .waiting:
                connection.cancel()
                Task { @MainActor in self?.resolved(name: name, host: nil) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        // Garde-fou : abandon après 5 s.
        queue.asyncAfter(deadline: .now() + 5) { [connection] in
            if connection.state != .cancelled { connection.cancel() }
        }
    }

    nonisolated static func ipv4(from endpoint: NWEndpoint?) -> String? {
        guard case .hostPort(let host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let addr):
            return addr.rawValue.map(String.init).joined(separator: ".")
        case .name(let name, _):
            return name
        default:
            return nil
        }
    }

    private func resolved(name: String, host: String?) {
        resolving.remove(name)
        guard let host, let i = speakers.firstIndex(where: { $0.name == name }) else { return }
        speakers[i].host = host
        Self.log.info("Enceinte « \(name, privacy: .public) » trouvée en \(host, privacy: .public)")
    }
}
