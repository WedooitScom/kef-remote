import Foundation

/// Surface commune au client réel (`KEFHTTPClient`) et au faux client de démo
/// (`DemoSpeakerClient`). `SpeakerStore` ne connaît que ce protocole.
public protocol SpeakerClient: Sendable {
    /// Lecture complète de l'état (à la connexion / reconnexion).
    func fetchState() async throws -> SpeakerSnapshot
    /// Long polling : rend la main dès qu'un changement survient, au plus tard après `timeout` s.
    func pollEvents(timeout: Int) async throws -> SpeakerEvents
    /// Oublie l'abonnement aux événements (un nouveau sera créé au prochain `pollEvents`).
    func resetEventQueue() async
    /// Relit `player:player/data`.
    func playerInfo() async throws -> PlayerInfo

    func setPower(on: Bool) async throws
    func setSource(_ source: SpeakerSource) async throws
    func setVolume(_ volume: Int) async throws
    func control(_ command: PlayerControl) async throws

    // Radios airable
    func radioHistory() async throws -> [Station]
    func searchStations(_ query: String) async throws -> [Station]
    /// Joue une station et renvoie la station normalisée.
    @discardableResult
    func playStation(path: String) async throws -> Station
}

public enum KEFError: LocalizedError, Equatable, Sendable {
    case http(Int, String)
    case invalidResponse(String)
    case notAStation
    case stationUnavailable
    case searchFormMissing
    case noSearchResults
    case tooManyRedirects
    case queueExpired
    case offline
    case notConfigured
    case invalidHost(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let body): "Erreur HTTP \(code)\(body.isEmpty ? "" : " : \(body.prefix(120))")"
        case .invalidResponse(let what): "Réponse inattendue de l'enceinte (\(what))"
        case .notAStation: "Ce n'est pas une station airable"
        case .stationUnavailable: "Station introuvable ou injouable"
        case .searchFormMissing: "Formulaire de recherche introuvable"
        case .noSearchResults: "La recherche n'a pas renvoyé de résultats"
        case .tooManyRedirects: "Trop de redirections"
        case .queueExpired: "File d'événements expirée"
        case .offline: "Enceinte hors ligne"
        case .notConfigured: "Aucune enceinte configurée"
        case .invalidHost(let raw): "Adresse invalide : « \(raw) »"
        }
    }
}

/// Validation des adresses saisies par l'utilisateur.
public enum HostValidator {
    /// Nettoie une saisie (« http://192.168.1.20/ » → « 192.168.1.20 »).
    /// Accepte un nom d'hôte ou une IPv4, éventuellement suivi d'un port.
    public static func normalize(_ raw: String) throws -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["http://", "https://"] where host.lowercased().hasPrefix(scheme) {
            host = String(host.dropFirst(scheme.count))
        }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        let pattern = #"^[A-Za-z0-9.\-_]{1,253}(:\d{1,5})?$"#
        guard !host.isEmpty, host.range(of: pattern, options: .regularExpression) != nil else {
            throw KEFError.invalidHost(raw)
        }
        return host
    }
}

/// Message court et lisible pour une erreur (affiché dans l'UI).
public func describe(_ error: any Error) -> String {
    if let kef = error as? KEFError, let d = kef.errorDescription { return d }
    if let url = error as? URLError {
        if isLocalNetworkDenied(url) { return localNetworkDeniedMessage }
        switch url.code {
        case .timedOut: return "Délai dépassé"
        case .cannotConnectToHost, .cannotFindHost: return "Enceinte injoignable"
        case .notConnectedToInternet, .networkConnectionLost: return "Réseau indisponible"
        default: return url.localizedDescription
        }
    }
    return error.localizedDescription
}

public let localNetworkDeniedMessage =
    "Accès au réseau local refusé : autorisez KEF Remote dans Réglages Système › Confidentialité et sécurité › Réseau local"

/// macOS bloque l'accès au réseau local tant que l'utilisateur n'a pas accepté la demande
/// (ou l'a refusée) : URLSession échoue alors avec `notConnectedToInternet` et un chemin
/// réseau « unsatisfied (Local network prohibited) ».
public func isLocalNetworkDenied(_ error: URLError) -> Bool {
    guard error.code == .notConnectedToInternet || error.code == .cannotConnectToHost else { return false }
    let info = (error as NSError).userInfo
    return info.values.contains { String(describing: $0).localizedCaseInsensitiveContains("Local network prohibited") }
}
