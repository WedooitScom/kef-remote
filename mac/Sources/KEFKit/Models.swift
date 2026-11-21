import Foundation

// MARK: - Sources

/// Entrées physiques des enceintes KEF (valeurs de `kefPhysicalSource`).
public enum SpeakerSource: String, CaseIterable, Sendable, Codable, Identifiable {
    case wifi, bluetooth, tv, optic, coaxial, analog, usb

    public var id: String { rawValue }

    /// Libellé affiché (UI en français).
    public var label: String {
        switch self {
        case .wifi: "Wi‑Fi"
        case .bluetooth: "Bluetooth"
        case .tv: "TV"
        case .optic: localized("Optique")
        case .coaxial: localized("Coaxial")
        case .analog: localized("Analogique")
        case .usb: "USB"
        }
    }

    /// SF Symbol associé.
    public var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .tv: "tv"
        case .optic: "fibrechannel"
        case .coaxial: "cable.coaxial"
        case .analog: "cable.connector"
        case .usb: "cable.connector.horizontal"
        }
    }

    /// Analyse tolérante (le README de pykefcontrol parle de « optical », le firmware dit « optic »).
    public static func parse(_ raw: String?) -> SpeakerSource? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch s {
        case "optical": return .optic
        case "coax": return .coaxial
        case "aux": return .analog
        default: return SpeakerSource(rawValue: s)
        }
    }
}

public enum PowerState: String, Sendable, Equatable {
    case on, standby, unknown
}

public enum PlaybackState: String, Sendable, Equatable {
    case playing, paused, stopped

    public init(raw: String?) {
        self = PlaybackState(rawValue: raw ?? "") ?? .stopped
    }
}

/// Commandes de transport (`player:player/control`, rôle `activate`).
public enum PlayerControl: String, Sendable {
    /// Bascule lecture/pause (c'est la commande utilisée par pykefcontrol). Sans effet sur
    /// un flux en direct (radio airable) : l'enceinte n'y annonce pas de clé `pause`.
    case pause
    /// Arrêt : seule façon d'interrompre un flux en direct (reprise = rejouer la station).
    case stop
    case next
    case previous
}

/// Commandes acceptées par le contenu en cours, d'après le bloc `controls` de
/// `player:player/data`. `nil` = clé absente (l'enceinte ne se prononce pas).
///
/// Relevé sur une radio airable en direct : `{like, playMode, seekTime, previous,
/// seekTrack, next_, seekBytes, dislike}` tous à `false` et **aucune clé `pause`**.
public struct TransportCapabilities: Sendable, Equatable {
    public var pause: Bool?
    public var next: Bool?
    public var previous: Bool?
    public var seek: Bool?

    public init(pause: Bool? = nil, next: Bool? = nil, previous: Bool? = nil, seek: Bool? = nil) {
        self.pause = pause
        self.next = next
        self.previous = previous
        self.seek = seek
    }
}

// MARK: - Stations

/// Station de radio airable, au même format que `favorites.json` du client web.
public struct Station: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var path: String
    public var icon: String?
    public var description: String?

    public init(id: String, title: String, path: String, icon: String? = nil, description: String? = nil) {
        self.id = id
        self.title = title
        self.path = path
        self.icon = icon
        self.description = description
    }

    /// Deux stations désignent la même radio si l'id ou le path coïncident.
    public func isSameStation(as other: Station?) -> Bool {
        guard let other else { return false }
        return id == other.id || path == other.path
    }
}

// MARK: - Lecteur

/// Contenu de `player:player/data` réduit à ce dont l'UI a besoin.
public struct PlayerInfo: Sendable, Equatable {
    public var state: PlaybackState
    public var title: String?
    public var artist: String?
    public var album: String?
    /// URL brute de la pochette (http(s), `data:` ou `demo://…` en mode démo).
    public var coverURL: String?
    public var serviceID: String?
    /// Durée en millisecondes, `nil` pour un flux sans fin (radio…).
    public var durationMs: Int?
    /// Flux en direct (radio) : pas de progression ni de piste suivante.
    public var isLive: Bool
    /// Station airable en cours (si c'est une radio airable).
    public var station: Station?
    public var canSkip: Bool
    /// Bloc `controls` analysé (`nil` si l'enceinte ne l'a pas envoyé).
    public var capabilities: TransportCapabilities?

    public init(state: PlaybackState = .stopped, title: String? = nil, artist: String? = nil,
                album: String? = nil, coverURL: String? = nil, serviceID: String? = nil,
                durationMs: Int? = nil, isLive: Bool = false, station: Station? = nil, canSkip: Bool = true,
                capabilities: TransportCapabilities? = nil) {
        self.state = state
        self.title = title
        self.artist = artist
        self.album = album
        self.coverURL = coverURL
        self.serviceID = serviceID
        self.durationMs = durationMs
        self.isLive = isLive
        self.station = station
        self.canSkip = canSkip
        self.capabilities = capabilities
    }

    public static let stopped = PlayerInfo()

    public var isAirableRadio: Bool { serviceID == KEFParser.airableService }

    /// Piste suivante possible (`controls.next_`, sinon déduit du type de flux).
    public var canGoNext: Bool { capabilities?.next ?? (canSkip && !isLive) }
    /// Piste précédente possible (`controls.previous`, sinon déduit du type de flux).
    public var canGoPrevious: Bool { capabilities?.previous ?? (canSkip && !isLive) }
}

// MARK: - État complet

/// Photographie de l'état de l'enceinte (lecture complète à la connexion).
public struct SpeakerSnapshot: Sendable, Equatable {
    public var name: String?
    public var model: String?
    public var modelLabel: String?
    public var firmware: String?
    public var mac: String?
    public var power: PowerState
    public var source: SpeakerSource?
    public var sources: [SpeakerSource]
    public var volume: Int
    /// Drapeau `settings:/mediaPlayer/mute` de l'enceinte.
    public var speakerMuted: Bool
    public var player: PlayerInfo
    public var positionMs: Int?

    public init(name: String? = nil, model: String? = nil, modelLabel: String? = nil, firmware: String? = nil,
                mac: String? = nil, power: PowerState = .unknown, source: SpeakerSource? = nil,
                sources: [SpeakerSource] = KEFParser.sources(forModel: "LS50WII"), volume: Int = 0,
                speakerMuted: Bool = false, player: PlayerInfo = .stopped, positionMs: Int? = nil) {
        self.name = name
        self.model = model
        self.modelLabel = modelLabel
        self.firmware = firmware
        self.mac = mac
        self.power = power
        self.source = source
        self.sources = sources
        self.volume = volume
        self.speakerMuted = speakerMuted
        self.player = player
        self.positionMs = positionMs
    }

    public static let empty = SpeakerSnapshot()

    /// Son coupé : volume nul (méthode pykefcontrol) ou drapeau mute de l'enceinte.
    public var isMuted: Bool { volume == 0 || speakerMuted }
    public var isOn: Bool { power == .on }
    public var isPlaying: Bool { isOn && player.state == .playing }

    /// Station airable en cours de lecture (uniquement en Wi‑Fi, enceinte allumée).
    public var currentStation: Station? {
        guard isOn, source == .wifi || source == nil else { return nil }
        return player.station
    }
}

// MARK: - Événements

/// Changements remontés par la file d'événements (`/api/event/pollQueue`).
public struct SpeakerEvents: Sendable, Equatable {
    public var power: PowerState?
    /// Valeur brute de `kefPhysicalSource` (peut valoir `standby`).
    public var source: String?
    public var volume: Int?
    public var mute: Bool?
    public var player: PlayerInfo?
    public var positionMs: Int?
    public var deviceName: String?

    public init(power: PowerState? = nil, source: String? = nil, volume: Int? = nil, mute: Bool? = nil,
                player: PlayerInfo? = nil, positionMs: Int? = nil, deviceName: String? = nil) {
        self.power = power
        self.source = source
        self.volume = volume
        self.mute = mute
        self.player = player
        self.positionMs = positionMs
        self.deviceName = deviceName
    }

    public var isEmpty: Bool { self == SpeakerEvents() }

    /// Fusionne des événements plus récents.
    public mutating func merge(_ other: SpeakerEvents) {
        power = other.power ?? power
        source = other.source ?? source
        volume = other.volume ?? volume
        mute = other.mute ?? mute
        player = other.player ?? player
        positionMs = other.positionMs ?? positionMs
        deviceName = other.deviceName ?? deviceName
    }
}
