import Foundation

// Décisions de transport (pause / reprise / précédent / suivant), sans état ni réseau :
// testées seules, appliquées par `SpeakerStore` et l'app.

/// Façon d'interrompre la lecture en cours.
public enum PauseStrategy: Equatable, Sendable {
    /// `{"control":"pause"}` (bascule), puis vérification : repli sur `stop` si l'état ne change pas.
    case pause
    /// `{"control":"stop"}` : flux en direct ; la reprise rejoue la station.
    case stop
}

/// Façon de reprendre la lecture.
public enum ResumeAction: Equatable, Sendable {
    /// Rejouer la station (re-résolution de la row audio, comme une lecture de station).
    case playStation(Station)
    /// `{"control":"pause"}` (bascule pause → lecture).
    case toggle
}

public enum SkipDirection: Sendable, Equatable {
    case previous, next
}

/// Ce que font les boutons précédent / suivant pour le contenu en cours.
public struct SkipPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Zapper vers cette station (radio airable).
        case station(Station)
        /// Envoyer `previous` / `next` à l'enceinte.
        case track
        /// Rien à faire (bouton désactivé).
        case none
    }

    public var action: Action
    /// Vrai quand les boutons zappent entre stations (radio airable).
    public var isRadio: Bool
    /// Libellé court (VoiceOver, menu) : « Radio suivante », « Piste précédente »…
    public var label: String
    /// Infobulle (explique aussi pourquoi le bouton est désactivé).
    public var help: String

    public init(action: Action, isRadio: Bool = false, label: String, help: String) {
        self.action = action
        self.isRadio = isRadio
        self.label = label
        self.help = help
    }

    public var isEnabled: Bool { action != .none }
}

public enum TransportLogic {
    // MARK: Pause / reprise

    /// Pause si l'enceinte l'annonce (`controls.pause`) ; sinon arrêt pour un flux en direct
    /// (radio : aucune clé `pause`, la commande serait ignorée) ; sinon pause vérifiée.
    public static func pauseStrategy(for player: PlayerInfo) -> PauseStrategy {
        if let pause = player.capabilities?.pause { return pause ? .pause : .stop }
        return player.isLive ? .stop : .pause
    }

    /// Reprise : un contenu en pause (non live) reprend par bascule ; une radio interrompue
    /// (ou dont l'enceinte a oublié `mediaRoles` après l'arrêt) est rejouée.
    public static func resumeAction(player: PlayerInfo, stoppedStation: Station?) -> ResumeAction {
        if player.state == .paused, !player.isLive { return .toggle }
        if player.isLive, let station = player.station ?? stoppedStation { return .playStation(station) }
        if let stoppedStation, player.title == nil || player.isAirableRadio { return .playStation(stoppedStation) }
        return .toggle
    }

    // MARK: Zapping entre stations

    /// Liste de zapping : les favoris, sinon l'historique / les suggestions.
    public static func zapList(favorites: [Station], fallback: [Station]) -> [Station] {
        favorites.isEmpty ? fallback : favorites
    }

    /// Station voisine dans `list` (bouclage aux extrémités). Si la station courante n'y
    /// figure pas : suivant = première, précédent = dernière. `nil` s'il n'y a pas d'autre station.
    public static func adjacentStation(_ direction: SkipDirection, current: Station?, in list: [Station]) -> Station? {
        guard !list.isEmpty else { return nil }
        guard let current, let index = list.firstIndex(where: { $0.isSameStation(as: current) }) else {
            return direction == .next ? list.first : list.last
        }
        guard list.count > 1 else { return nil }
        let offset = direction == .next ? 1 : list.count - 1
        return list[(index + offset) % list.count]
    }

    /// Plan des boutons précédent / suivant.
    /// - `station` : radio airable en cours ou interrompue (`nil` = autre contenu).
    public static func skipPlan(_ direction: SkipDirection, snapshot: SpeakerSnapshot, isOnline: Bool,
                                station: Station?, favorites: [Station], fallback: [Station]) -> SkipPlan {
        let next = direction == .next
        let shortcut = next ? "⌘→" : "⌘←"
        let trackLabel = next ? "Piste suivante" : "Piste précédente"
        guard isOnline, snapshot.isOn else {
            return SkipPlan(action: .none, label: trackLabel, help: "\(trackLabel) (\(shortcut))")
        }
        let wifi = snapshot.source == .wifi || snapshot.source == nil
        if wifi, station != nil || snapshot.player.isAirableRadio {
            let label = next ? "Radio suivante" : "Radio précédente"
            let list = zapList(favorites: favorites, fallback: fallback)
            guard let target = adjacentStation(direction, current: station, in: list) else {
                let why = list.isEmpty ? "aucune radio favorite ni récente" : "aucune autre radio dans la liste"
                return SkipPlan(action: .none, isRadio: true, label: label, help: "\(label) : \(why)")
            }
            let origin = favorites.isEmpty ? " (radios récentes)" : ""
            return SkipPlan(action: .station(target), isRadio: true, label: label,
                            help: "\(label) : « \(target.title) »\(origin) (\(shortcut))")
        }
        if snapshot.player.state == .stopped && snapshot.player.title == nil {
            return SkipPlan(action: .none, label: trackLabel, help: "\(trackLabel) : rien en lecture")
        }
        let allowed = next ? snapshot.player.canGoNext : snapshot.player.canGoPrevious
        guard allowed else {
            return SkipPlan(action: .none, label: trackLabel, help: "\(trackLabel) : non disponible pour ce contenu")
        }
        return SkipPlan(action: .track, label: trackLabel, help: "\(trackLabel) (\(shortcut))")
    }
}
