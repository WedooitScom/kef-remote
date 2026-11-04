import Foundation

/// Faux client en mémoire (mode démo `--demo` / `KEF_DEMO=1`, et tests).
///
/// Simule une paire de LS50 Wireless II : pistes fictives qui avancent dans le
/// temps, radios fictives, file d'événements en long polling. Mêmes formes de
/// données que la vraie enceinte, via le protocole `SpeakerClient`.
public actor DemoSpeakerClient: SpeakerClient {
    struct Track { let title, artist, album: String; let durationMs: Int; let hue: Int }
    struct DemoStation { let n: Int; let title, desc: String; let hue: Int; let now: String }

    static let tracks: [Track] = [
        Track(title: "Uni-Q Sunrise", artist: "The Coaxials", album: "Concentric", durationMs: 214_000, hue: 24),
        Track(title: "Tangerine Waveguide", artist: "Maidstone Drift", album: "Kent Sessions", durationMs: 187_000, hue: 200),
        Track(title: "Low Frequency Letters", artist: "Nora Vale", album: "Port & Bass", durationMs: 248_000, hue: 280),
        Track(title: "Metamaterial", artist: "Absorption Theory", album: "MAT", durationMs: 199_000, hue: 150),
        Track(title: "Standby Lullaby", artist: "Wireless Two", album: "Night Mode", durationMs: 231_000, hue: 340),
    ]

    static let stations: [DemoStation] = [
        DemoStation(n: 1, title: "Radio Cuivre", desc: "Jazz et soul, en direct de Maidstone", hue: 24, now: "Brass Tweeter Blues"),
        DemoStation(n: 2, title: "Onde Coaxiale FM", desc: "Pop indé et nouveautés", hue: 200, now: "Concentric Hearts"),
        DemoStation(n: 3, title: "Basse Fréquence", desc: "Électro, house et deep", hue: 280, now: "Port Resonance (Extended)"),
        DemoStation(n: 4, title: "Classique Uni-Q", desc: "Musique classique 24h/24", hue: 45, now: "Nocturne pour enceinte seule"),
        DemoStation(n: 5, title: "Kent Info", desc: "Actualités et débats", hue: 0, now: "Le journal de 18 h"),
        DemoStation(n: 6, title: "Métamatériau Rock", desc: "Rock et métal", hue: 150, now: "Absorb the Noise"),
        DemoStation(n: 7, title: "Veille Lounge", desc: "Chill-out, lounge et ambient", hue: 320, now: "Standby Lullaby (Radio Edit)"),
        DemoStation(n: 8, title: "Radio Cuivre Groove", desc: "Funk et groove", hue: 30, now: "Copper Funk Machine"),
        DemoStation(n: 9, title: "Ondes Monde", desc: "Musiques du monde", hue: 100, now: "Wireless Two Step"),
    ]

    /// `controls` relevé sur une radio airable : ni pause, ni précédent / suivant.
    static let liveCapabilities = TransportCapabilities(pause: nil, next: false, previous: false, seek: false)

    /// Pochette générée par l'UI (dégradé + cercles Uni-Q) : `demo://art?hue=24`.
    public static func artURL(hue: Int) -> String { "demo://art?hue=\(hue)" }

    /// Stations fictives du mode démo (favoris de démonstration, captures d'écran).
    public static var demoStations: [Station] { stations.map(station) }

    static func station(_ s: DemoStation) -> Station {
        Station(id: "demo://radio/\(s.n)", title: s.title, path: "demo:radio/\(s.n)",
                icon: artURL(hue: s.hue), description: s.desc)
    }

    // État simulé
    private var name = "Salon (démo)"
    private var power: PowerState = .on
    private var source: SpeakerSource = .wifi
    private var lastSource: SpeakerSource = .wifi
    private var volume = 32
    private var speakerMuted = false
    private var trackIndex = 0
    private var state: PlaybackState = .playing
    private var positionMs = 42_000
    private var clock = Date()
    private var stationNumber: Int?
    private var history: [Int] = [3, 1, 7]

    private var pending = SpeakerEvents()
    private let latency: Duration

    /// Délais simulés : `latency` pour les commandes (0 dans les tests).
    public init(latency: Duration = .milliseconds(60), poweredOn: Bool = true) {
        self.latency = latency
        self.power = poweredOn ? .on : .standby
    }

    // MARK: Mécanique interne

    private func nowPosition() -> Int {
        if state == .playing && power == .on {
            return positionMs + Int(Date().timeIntervalSince(clock) * 1000)
        }
        return positionMs
    }

    private func freeze() {
        positionMs = nowPosition()
        clock = Date()
    }

    private func currentPlayer() -> PlayerInfo {
        guard power == .on, source == .wifi else { return .stopped }
        if let n = stationNumber, let st = Self.stations.first(where: { $0.n == n }) {
            // Comme la vraie enceinte : après « stop », le lecteur ne décrit plus la radio.
            guard state != .stopped else { return .stopped }
            return PlayerInfo(state: state, title: st.now, artist: st.title, coverURL: Self.artURL(hue: st.hue),
                              serviceID: KEFParser.airableService, durationMs: nil, isLive: true,
                              station: Self.station(st), canSkip: false, capabilities: Self.liveCapabilities)
        }
        let t = Self.tracks[trackIndex]
        return PlayerInfo(state: state, title: t.title, artist: t.artist, album: t.album,
                          coverURL: Self.artURL(hue: t.hue), serviceID: "demo", durationMs: t.durationMs,
                          capabilities: TransportCapabilities(pause: true, next: true, previous: true, seek: false))
    }

    private func notifyPlayer() {
        pending.player = currentPlayer()
        pending.positionMs = nowPosition()
    }

    private func maybeAdvance() {
        guard stationNumber == nil, power == .on, source == .wifi else { return }
        if nowPosition() >= Self.tracks[trackIndex].durationMs {
            trackIndex = (trackIndex + 1) % Self.tracks.count
            positionMs = 0
            clock = Date()
            notifyPlayer()
        }
    }

    private func simulateLatency() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
    }

    // MARK: SpeakerClient

    public func fetchState() async throws -> SpeakerSnapshot {
        try await simulateLatency()
        maybeAdvance()
        return SpeakerSnapshot(
            name: name, model: "LS50WII", modelLabel: "LS50 Wireless II", firmware: "V41192-demo",
            mac: "84:17:15:DE:M0:00", power: power, source: power == .on ? source : nil,
            sources: KEFParser.sources(forModel: "LS50WII"), volume: volume, speakerMuted: speakerMuted,
            player: currentPlayer(), positionMs: nowPosition()
        )
    }

    public func pollEvents(timeout: Int) async throws -> SpeakerEvents {
        let playing = power == .on && state == .playing && source == .wifi
        // Comme l'enceinte abonnée à playTime : au moins une remontée par seconde en lecture.
        let wait = playing ? min(Double(timeout), 1.0) : Double(timeout)
        let deadline = Date().addingTimeInterval(wait)
        while pending.isEmpty && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        maybeAdvance()
        var events = pending
        pending = SpeakerEvents()
        if playing && events.positionMs == nil { events.positionMs = nowPosition() }
        return events
    }

    public func resetEventQueue() async {}

    public func playerInfo() async throws -> PlayerInfo { currentPlayer() }

    public func setPower(on: Bool) async throws {
        try await simulateLatency()
        freeze()
        if on {
            power = .on
            source = lastSource
            pending.source = source.rawValue
        } else {
            power = .standby
            pending.source = "standby"
        }
        pending.power = power
        notifyPlayer()
    }

    public func setSource(_ newSource: SpeakerSource) async throws {
        try await simulateLatency()
        freeze()
        power = .on
        source = newSource
        lastSource = newSource
        pending.power = .on
        pending.source = newSource.rawValue
        notifyPlayer()
    }

    public func setVolume(_ v: Int) async throws {
        try await simulateLatency()
        volume = max(0, min(100, v))
        pending.volume = volume
    }

    public func control(_ command: PlayerControl) async throws {
        try await simulateLatency()
        guard power == .on else { return }
        switch command {
        case .pause:
            // Flux en direct : l'enceinte ignore « pause » (pas de clé `pause` dans `controls`).
            guard stationNumber == nil else { return }
            freeze()
            state = state == .playing ? .paused : .playing
        case .stop:
            freeze()
            state = .stopped
        case .next:
            stationNumber = nil
            trackIndex = (trackIndex + 1) % Self.tracks.count
            positionMs = 0
            clock = Date()
            state = .playing
        case .previous:
            // Comme la plupart des lecteurs : retour au début si on a dépassé 3 s.
            if stationNumber == nil && nowPosition() <= 3000 {
                trackIndex = (trackIndex - 1 + Self.tracks.count) % Self.tracks.count
            }
            stationNumber = nil
            positionMs = 0
            clock = Date()
        }
        notifyPlayer()
    }

    public func radioHistory() async throws -> [Station] {
        history.compactMap { n in Self.stations.first(where: { $0.n == n }).map(Self.station) }
    }

    public func searchStations(_ query: String) async throws -> [Station] {
        if latency > .zero { try await Task.sleep(for: .milliseconds(150)) }
        let q = Self.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        return Self.stations.filter { Self.fold($0.title).contains(q) || Self.fold($0.desc).contains(q) }.map(Self.station)
    }

    @discardableResult
    public func playStation(path: String) async throws -> Station {
        guard path.hasPrefix("demo:radio/"), let n = Int(path.dropFirst("demo:radio/".count)),
              let st = Self.stations.first(where: { $0.n == n })
        else { throw KEFError.notAStation }
        try await simulateLatency()
        stationNumber = n
        state = .playing
        power = .on
        source = .wifi
        lastSource = .wifi
        positionMs = 0
        clock = Date()
        history = [n] + history.filter { $0 != n }.prefix(9)
        pending.power = .on
        pending.source = "wifi"
        notifyPlayer()
        return Self.station(st)
    }

    /// Minuscules sans accents, pour une recherche tolérante.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
