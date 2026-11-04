import Foundation
import Observation
import os

public enum ConnectionStatus: Equatable, Sendable {
    case notConfigured
    case connecting
    case online
    case offline(String)

    public var isOnline: Bool { self == .online }
}

/// État observable de l'enceinte + boucle de fond (lecture complète, long polling,
/// reconnexion avec backoff) + commandes avec mises à jour optimistes.
///
/// Les commandes modifient l'état immédiatement (optimisme) ; l'enceinte confirme
/// ensuite via les événements. En cas d'échec, l'état précédent est restauré.
@MainActor
@Observable
public final class SpeakerStore {
    public private(set) var status: ConnectionStatus = .notConfigured
    public private(set) var snapshot = SpeakerSnapshot.empty
    /// Position connue (ms) et instant de la mesure, pour l'estimation en continu.
    public private(set) var positionMs: Int?
    public private(set) var positionDate = Date()
    /// Dernière erreur de commande (affichée brièvement par l'UI).
    public var commandError: String?
    /// Station en cours de lancement (indicateur sur la tuile).
    public private(set) var loadingStationID: String?
    /// Dernière station airable vue en lecture (reprise si l'enceinte oublie `mediaRoles`).
    public private(set) var lastStation: Station?
    /// Radio interrompue par « pause » (= stop sur un flux en direct), à rejouer à la reprise.
    public private(set) var stoppedStation: Station?

    public let backoffMin: Double
    public let backoffMax: Double
    public let pollTimeout: Int

    private var client: (any SpeakerClient)?
    private var generation = 0
    private var loopTask: Task<Void, Never>?
    private var backoffSleep: Task<Void, Never>?

    // Volume : envoi « au fil de l'eau » du dernier volume demandé (curseur).
    private var pendingVolume: Int?
    private var volumeTask: Task<Void, Never>?
    private var volumeLockUntil = Date.distantPast
    /// Dernier volume non nul (pour rétablir le son).
    public private(set) var lastAudibleVolume = 20

    static let playRetries = 4
    static let playRetryDelay: Duration = .milliseconds(1500)
    private static let log = Logger(subsystem: "fr.wedooit.kefremote", category: "store")

    public init(backoffMin: Double = 1, backoffMax: Double = 30, pollTimeout: Int = 10) {
        self.backoffMin = backoffMin
        self.backoffMax = backoffMax
        self.pollTimeout = pollTimeout
    }

    public var hasClient: Bool { client != nil }

    // MARK: - Cycle de vie

    /// Change d'enceinte (ou de client démo) à chaud. `nil` = aucune enceinte configurée.
    public func connect(_ newClient: (any SpeakerClient)?) {
        loopTask?.cancel()
        backoffSleep?.cancel()
        volumeTask?.cancel()
        volumeTask = nil
        pendingVolume = nil
        generation += 1
        client = newClient
        snapshot = .empty
        positionMs = nil
        commandError = nil
        loadingStationID = nil
        lastStation = nil
        stoppedStation = nil
        guard let newClient else {
            status = .notConfigured
            return
        }
        status = .connecting
        let gen = generation
        loopTask = Task { [weak self] in
            await self?.run(client: newClient, generation: gen)
        }
    }

    public func stop() {
        loopTask?.cancel()
        backoffSleep?.cancel()
        loopTask = nil
    }

    /// Interrompt l'attente de backoff et retente immédiatement.
    public func retryNow() {
        backoffSleep?.cancel()
    }

    private func isCurrent(_ gen: Int) -> Bool { gen == generation && !Task.isCancelled }

    private func run(client: any SpeakerClient, generation gen: Int) async {
        var backoff = backoffMin
        while isCurrent(gen) {
            do {
                if status != .online {
                    let snap = try await client.fetchState()
                    guard isCurrent(gen) else { return }
                    apply(snap)
                    status = .online
                    backoff = backoffMin
                }
                let events = try await client.pollEvents(timeout: pollTimeout)
                guard isCurrent(gen) else { return }
                apply(events)
            } catch {
                guard isCurrent(gen) else { return }
                Self.log.info("Enceinte injoignable : \(describe(error), privacy: .public) ; nouvel essai dans \(backoff) s")
                await client.resetEventQueue()
                status = .offline(describe(error))
                let delay = backoff
                let sleeper = Task { _ = try? await Task.sleep(for: .seconds(delay)) }
                backoffSleep = sleeper
                await sleeper.value
                backoffSleep = nil
                backoff = min(backoff * 2, backoffMax)
            }
        }
    }

    // MARK: - Application de l'état

    func apply(_ snap: SpeakerSnapshot) {
        var s = snap
        // Garde la station connue si l'enceinte ne la renvoie pas (relecture partielle).
        if s.player.station == nil, s.player.isAirableRadio { s.player.station = snapshot.player.station }
        s.player = reconcileStopped(s.player, power: s.power, source: s.source)
        snapshot = s
        if s.volume > 0 { lastAudibleVolume = s.volume }
        positionMs = s.positionMs
        positionDate = Date()
    }

    func apply(_ ev: SpeakerEvents) {
        guard !ev.isEmpty else { return }
        var s = snapshot
        if let p = ev.power { s.power = p }
        if let raw = ev.source {
            if raw == "standby" {
                s.power = .standby
            } else {
                s.source = SpeakerSource.parse(raw) ?? s.source
                if ev.power == nil { s.power = .on }
            }
        }
        if let m = ev.mute { s.speakerMuted = m }
        if let v = ev.volume {
            // Pendant un réglage au curseur, on ignore les échos intermédiaires de l'enceinte.
            if Date() >= volumeLockUntil || v == s.volume {
                s.volume = v
                if v > 0 { lastAudibleVolume = v }
            }
        }
        if let name = ev.deviceName { s.name = name }
        if var p = ev.player {
            if p.station == nil, p.isAirableRadio { p.station = snapshot.player.station }
            s.player = p
        }
        s.player = reconcileStopped(s.player, power: s.power, source: s.source)
        if let pos = ev.positionMs {
            positionMs = pos
            positionDate = Date()
        } else if ev.player != nil, ev.player?.title != snapshot.player.title {
            positionMs = 0
            positionDate = Date()
        }
        snapshot = s
    }

    /// Mémorise la station en cours et, après un arrêt de radio, garde la station affichée
    /// (l'enceinte peut renvoyer un lecteur vide après `stop`) pour pouvoir la relancer.
    private func reconcileStopped(_ player: PlayerInfo, power: PowerState, source: SpeakerSource?) -> PlayerInfo {
        var p = player
        if p.state == .playing, let station = p.station { lastStation = station }
        guard let stopped = stoppedStation else { return p }
        if p.state == .playing || power == .standby || (source != nil && source != .wifi) {
            // Autre chose joue (ou la radio a repris), veille, autre entrée : plus rien à reprendre.
            stoppedStation = nil
            return p
        }
        if p.station == nil, p.serviceID == nil || p.isAirableRadio {
            p.station = stopped
            p.serviceID = KEFParser.airableService
            p.isLive = true
            p.canSkip = false
        }
        return p
    }

    /// Station airable en cours ou interrompue (zapping, reprise).
    public var activeStation: Station? {
        snapshot.currentStation ?? (snapshot.isOn && (snapshot.source == .wifi || snapshot.source == nil) ? stoppedStation : nil)
    }

    /// Position estimée (ms) à l'instant `date`, bornée par la durée.
    public func estimatedPosition(at date: Date = Date()) -> Int? {
        guard var pos = positionMs else { return nil }
        if snapshot.isPlaying { pos += Int(date.timeIntervalSince(positionDate) * 1000) }
        if let d = snapshot.player.durationMs { pos = min(pos, d) }
        return max(0, pos)
    }

    // MARK: - Commandes

    private func requireClient() throws -> any SpeakerClient {
        guard let client else { throw KEFError.notConfigured }
        guard status == .online else { throw KEFError.offline }
        return client
    }

    /// Exécute une commande avec mise à jour optimiste ; restaure l'état en cas d'échec.
    /// Renvoie `true` si l'enceinte a accepté la commande.
    @discardableResult
    private func send(optimistic: ((inout SpeakerSnapshot) -> Void)? = nil,
                      _ operation: @Sendable (any SpeakerClient) async throws -> Void) async -> Bool {
        let client: any SpeakerClient
        do { client = try requireClient() } catch {
            commandError = describe(error)
            return false
        }
        let before = snapshot
        let gen = generation
        if let optimistic { optimistic(&snapshot) }
        do {
            try await operation(client)
            commandError = nil
            return true
        } catch {
            guard gen == generation else { return false }
            if optimistic != nil { snapshot = before }
            commandError = "Commande refusée : \(describe(error))"
            retryNow()
            return false
        }
    }

    public func setPower(on: Bool) async {
        await send(optimistic: { s in
            s.power = on ? .on : .standby
            if !on { s.player.state = .stopped }
        }) { try await $0.setPower(on: on) }
    }

    public func togglePower() async {
        await setPower(on: !snapshot.isOn)
    }

    public func selectSource(_ source: SpeakerSource) async {
        await send(optimistic: { s in
            s.source = source
            s.power = .on
        }) { try await $0.setSource(source) }
    }

    /// Règle le volume (appel synchrone, adapté à un curseur) : l'état change tout de suite,
    /// l'envoi à l'enceinte est regroupé (seule la dernière valeur compte).
    public func setVolume(_ volume: Int) {
        let v = max(0, min(100, volume))
        guard let client, status == .online else {
            commandError = describe(client == nil ? KEFError.notConfigured : KEFError.offline)
            return
        }
        snapshot.volume = v
        if v > 0 {
            lastAudibleVolume = v
            snapshot.speakerMuted = false
        }
        pendingVolume = v
        volumeLockUntil = Date().addingTimeInterval(1.5)
        guard volumeTask == nil else { return }
        let gen = generation
        volumeTask = Task { [weak self] in
            while let self, gen == self.generation, let target = self.pendingVolume {
                self.pendingVolume = nil
                do {
                    try await client.setVolume(target)
                } catch {
                    self.commandError = "Volume : \(describe(error))"
                    break
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
            guard let self, gen == self.generation else { return }
            self.volumeTask = nil
            self.volumeLockUntil = Date().addingTimeInterval(0.8)
        }
    }

    public func adjustVolume(by delta: Int) {
        setVolume(snapshot.volume + delta)
    }

    /// Couper le son = volume 0 en mémorisant le volume courant (comme pykefcontrol) ;
    /// rétablir = revenir au dernier volume audible.
    public func toggleMute() {
        if snapshot.isMuted {
            snapshot.speakerMuted = false
            setVolume(max(1, lastAudibleVolume))
        } else {
            if snapshot.volume > 0 { lastAudibleVolume = snapshot.volume }
            setVolume(0)
        }
    }

    /// Délai avant de relire l'état après pause / arrêt (le lecteur met un instant à changer).
    static let verifyDelay: Duration = .milliseconds(700)

    /// Lecture / pause adaptée au contenu :
    /// - radio (flux en direct, sans clé `pause` dans `controls`) : `stop`, puis la reprise
    ///   rejoue la station (row audio re-résolue) ;
    /// - autre contenu : `pause` (bascule), état vérifié, repli sur `stop` s'il n'a pas changé.
    /// L'état change tout de suite (bouton, position figée), puis il est réconcilié.
    public func playPause() async {
        guard let client, status == .online else {
            commandError = describe(client == nil ? KEFError.notConfigured : KEFError.offline)
            return
        }
        // Fige la position estimée avant de basculer l'état (la progression s'arrête net).
        if let current = estimatedPosition() {
            positionMs = current
            positionDate = Date()
        }
        let player = snapshot.player
        guard player.state == .playing else {
            switch TransportLogic.resumeAction(player: player, stoppedStation: stoppedStation) {
            case .playStation(let station):
                await playStation(station)
            case .toggle:
                await send(optimistic: { $0.player.state = .playing }) { try await $0.control(.pause) }
            }
            return
        }
        let gen = generation
        switch TransportLogic.pauseStrategy(for: player) {
        case .stop:
            await stopRadio(player, client: client)
        case .pause:
            guard await send(optimistic: { $0.player.state = .paused }, { try await $0.control(.pause) }) else { return }
            try? await Task.sleep(for: Self.verifyDelay)
            guard gen == generation, let fresh = try? await client.playerInfo(), gen == generation else { return }
            if fresh.state == .playing {
                // La pause n'a rien changé (flux non interruptible) : arrêt.
                Self.log.info("Pause sans effet, repli sur stop")
                await stopRadio(player, client: client, verify: false)
            } else {
                apply(SpeakerEvents(player: fresh))
            }
        }
    }

    /// Arrête la lecture (`stop`) en mémorisant la station pour la reprise.
    private func stopRadio(_ player: PlayerInfo, client: any SpeakerClient, verify: Bool = true) async {
        let gen = generation
        let previous = stoppedStation
        stoppedStation = player.station ?? (player.isAirableRadio ? lastStation : nil)
        let ok = await send(optimistic: { $0.player.state = .stopped }) { try await $0.control(.stop) }
        guard gen == generation else { return }
        guard ok else {
            stoppedStation = previous
            return
        }
        guard verify else { return }
        try? await Task.sleep(for: Self.verifyDelay)
        guard gen == generation, let fresh = try? await client.playerInfo(), gen == generation else { return }
        apply(SpeakerEvents(player: fresh))
    }

    public func nextTrack() async {
        guard snapshot.player.canGoNext else { return }
        await send { try await $0.control(.next) }
    }

    public func previousTrack() async {
        guard snapshot.player.canGoPrevious else { return }
        await send { try await $0.control(.previous) }
    }

    /// Joue une station ; allume l'enceinte et passe en Wi‑Fi si nécessaire.
    public func playStation(_ station: Station) async {
        let client: any SpeakerClient
        do { client = try requireClient() } catch {
            commandError = describe(error)
            return
        }
        let gen = generation
        loadingStationID = station.id
        defer { if gen == generation { loadingStationID = nil } }
        let woke = snapshot.power != .on || snapshot.source != .wifi
        if woke {
            // « physicalSource = wifi » réveille aussi l'enceinte depuis la veille.
            await selectSource(.wifi)
            guard gen == generation, snapshot.source == .wifi else { return }
        }
        let attempts = woke ? Self.playRetries : 1
        for attempt in 0..<attempts {
            do {
                let playing = try await client.playStation(path: station.path)
                guard gen == generation else { return }
                stoppedStation = nil
                lastStation = playing
                snapshot.player.station = playing
                snapshot.player.state = .playing
                snapshot.player.isLive = true
                snapshot.player.serviceID = KEFParser.airableService
                if snapshot.player.title == nil { snapshot.player.title = playing.title }
                commandError = nil
                return
            } catch let error as KEFError where error == .notAStation || error == .stationUnavailable {
                commandError = describe(error)
                return
            } catch {
                // Après un réveil, le lecteur met un peu de temps à accepter « play ».
                if attempt == attempts - 1 || gen != generation {
                    commandError = "Lecture impossible : \(describe(error))"
                    return
                }
                try? await Task.sleep(for: Self.playRetryDelay)
            }
        }
    }

    // MARK: - Radios (lecture seule)

    public func radioHistory() async throws -> [Station] {
        guard let client else { throw KEFError.notConfigured }
        return try await client.radioHistory()
    }

    public func searchStations(_ query: String) async throws -> [Station] {
        guard let client else { throw KEFError.notConfigured }
        return try await client.searchStations(query)
    }
}
