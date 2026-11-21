import Foundation

/// Analyse des réponses JSON de l'API NSDK (StreamUnlimited) des enceintes KEF.
///
/// Les formes traitées ici ont été relevées sur une LS50 Wireless II
/// (firmware V41192) et dans pykefcontrol / le client web Python.
public enum KEFParser {
    public static let airableService = "airableRadios"
    public static let stationMarker = "/id/airable/radio/"

    // MARK: Modèles

    public static let sourcesByModel: [String: [SpeakerSource]] = [
        "LS50WII": [.wifi, .bluetooth, .tv, .optic, .coaxial, .analog],
        "LS60": [.wifi, .bluetooth, .tv, .optic, .coaxial, .analog],
        "LSXII": [.wifi, .bluetooth, .tv, .optic, .usb, .analog],
        "LSXIILT": [.wifi, .bluetooth, .tv, .optic, .usb],
    ]

    public static let modelLabels: [String: String] = [
        "LS50WII": "LS50 Wireless II",
        "LS60": "LS60 Wireless",
        "LSXII": "LSX II",
        "LSXIILT": "LSX II LT",
    ]

    /// Ramène le préfixe du « release text » (ex. `LS50WII`, `LS50W2`, `LSX2LT`) à une clé connue.
    public static func normalizeModel(_ raw: String?) -> String {
        let s = (raw ?? "").uppercased().replacingOccurrences(of: " ", with: "")
        if s.contains("LSX") { return s.contains("LT") ? "LSXIILT" : "LSXII" }
        if s.contains("LS60") { return "LS60" }
        return "LS50WII"
    }

    public static func sources(forModel model: String) -> [SpeakerSource] {
        sourcesByModel[model] ?? sourcesByModel["LS50WII"]!
    }

    /// `settings:/releasetext` = `LS50WII_V41192` → (`LS50WII`, `V41192`).
    public static func splitRelease(_ release: String) -> (model: String, firmware: String?) {
        let parts = release.split(separator: "_", maxSplits: 1).map(String.init)
        return (parts.first ?? release, parts.count > 1 ? parts[1] : nil)
    }

    // MARK: getData

    /// `getData` renvoie un tableau à un élément : `[{"type":"i32_","i32_":30}]`.
    public static func firstItem(_ value: JSONValue) -> JSONValue? {
        if case .array(let a) = value { return a.first }
        return value
    }

    // MARK: Lecteur

    /// Analyse `player:player/data` (même forme dans `getData` et dans les événements).
    public static func playerInfo(_ data: JSONValue?) -> PlayerInfo {
        guard let data else { return .stopped }
        let track = data["trackRoles"]
        let meta = track?["mediaData"]?["metaData"]
        let station = station(fromPlayerData: data)
        let duration = data["status"]?["duration"]?.intValue
        let service = meta?["serviceID"]?.nonEmptyString
        let live = meta?["live"]?.boolValue == true || station != nil
        let capabilities = transportCapabilities(data["controls"])
        let canSkip = capabilities?.next ?? !live
        return PlayerInfo(
            state: PlaybackState(raw: data["state"]?.stringValue),
            title: track?["title"]?.nonEmptyString,
            artist: meta?["artist"]?.nonEmptyString,
            album: meta?["album"]?.nonEmptyString,
            coverURL: track?["icon"]?.nonEmptyString,
            serviceID: service,
            durationMs: (duration ?? 0) > 0 ? duration : nil,
            isLive: live,
            station: station,
            canSkip: canSkip,
            capabilities: capabilities
        )
    }

    /// Analyse le bloc `controls` (`next_` côté firmware, `next` toléré) ; `nil` s'il est absent.
    public static func transportCapabilities(_ controls: JSONValue?) -> TransportCapabilities? {
        guard let controls, controls.objectValue != nil else { return nil }
        return TransportCapabilities(
            pause: controls["pause"]?.boolValue,
            next: controls["next_"]?.boolValue ?? controls["next"]?.boolValue,
            previous: controls["previous"]?.boolValue,
            seek: controls["seekTime"]?.boolValue
        )
    }

    /// Station airable en cours d'après `mediaRoles` (sinon `nil`).
    public static func station(fromPlayerData data: JSONValue?) -> Station? {
        guard let roles = data?["mediaRoles"],
              roles["mediaData"]?["metaData"]?["serviceID"]?.stringValue == airableService
        else { return nil }
        return normalizeStation(roles)
    }

    // MARK: Stations

    /// Image la plus proche de 256 px (assez nette pour une tuile, légère).
    public static func bestImage(_ row: JSONValue) -> String? {
        let images = (row["images"]?["images"]?.arrayValue ?? []).filter { $0["url"]?.nonEmptyString != nil }
        if let best = images.min(by: {
            abs(($0["width"]?.intValue ?? 0) - 256) < abs(($1["width"]?.intValue ?? 0) - 256)
        }) {
            return best["url"]?.stringValue
        }
        return row["icon"]?.nonEmptyString
    }

    /// Ramène une row airable (container ou audio) à une `Station` ; `nil` si ce n'est pas une station
    /// (filtre « Par genre », dossier, podcast…).
    public static func normalizeStation(_ row: JSONValue?) -> Station? {
        guard let row, let path = row["path"]?.nonEmptyString, let title = row["title"]?.nonEmptyString,
              path.contains(stationMarker) || path.hasPrefix(demoStationPrefix)
        else { return nil }
        let meta = row["mediaData"]?["metaData"]
        return Station(
            id: row["id"]?.nonEmptyString ?? path,
            title: title,
            path: path,
            icon: bestImage(row),
            description: row["longDescription"]?.nonEmptyString ?? row["description"]?.nonEmptyString
                ?? meta?["slogan"]?.nonEmptyString
        )
    }

    /// Stations contenues dans une réponse `getRows` (les autres rows sont ignorées).
    public static func stations(fromRows response: JSONValue) -> [Station] {
        var seen = Set<String>()
        return (response["rows"]?.arrayValue ?? []).compactMap(normalizeStation).filter { seen.insert($0.id).inserted }
    }

    // MARK: Événements

    /// Analyse la réponse de `pollQueue` : `[{"path": …, "itemType": …, "itemValue": {…}}, …]`.
    /// Seule la dernière valeur de chaque chemin compte (comme pykefcontrol).
    public static func events(_ value: JSONValue) -> SpeakerEvents {
        var last: [String: JSONValue] = [:]
        for item in value.arrayValue ?? [] {
            guard let path = item["path"]?.stringValue else { continue }
            if let v = item["itemValue"] { last[path] = v }
        }
        var ev = SpeakerEvents()
        for (path, v) in last {
            switch path {
            case "settings:/kef/play/physicalSource":
                ev.source = v["kefPhysicalSource"]?.nonEmptyString
            case "player:player/data/playTime":
                ev.positionMs = v["i64_"]?.intValue
            case "player:volume":
                ev.volume = v["i32_"]?.intValue
            case "player:player/data":
                ev.player = playerInfo(v)
            case "settings:/kef/host/speakerStatus":
                if let s = v["kefSpeakerStatus"]?.stringValue { ev.power = s == "powerOn" ? .on : .standby }
            case "settings:/deviceName":
                ev.deviceName = v["string_"]?.nonEmptyString
            case "settings:/mediaPlayer/mute":
                ev.mute = v["bool_"]?.boolValue
            default:
                break
            }
        }
        return ev
    }

    /// Chemins auxquels le client s'abonne (sous-ensemble utile de la liste pykefcontrol).
    /// NB : pykefcontrol 0.9.3 n'abonne à `playTime` que via un paramètre déprécié
    /// (bug contourné dans le client Python) : ici on l'ajoute explicitement.
    public static let subscribedPaths: [String] = [
        "settings:/kef/host/speakerStatus",
        "settings:/kef/play/physicalSource",
        "player:volume",
        "settings:/mediaPlayer/mute",
        "player:player/data",
        "player:player/data/playTime",
        "settings:/deviceName",
    ]
}
