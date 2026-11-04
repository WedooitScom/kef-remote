import Foundation
import Testing
@testable import KEFKit

@Suite("Transport : controls, pause / stop, zapping")
struct TransportTests {
    static let a = Station(id: "a", title: "A", path: "airable:x/id/airable/radio/1")
    static let b = Station(id: "b", title: "B", path: "airable:x/id/airable/radio/2")
    static let c = Station(id: "c", title: "C", path: "airable:x/id/airable/radio/3")
    static let other = Station(id: "z", title: "Z", path: "airable:x/id/airable/radio/9")

    // MARK: Analyse de `controls`

    @Test func parsesLiveRadioControls() throws {
        // Réponse réelle (LS50 Wireless II, radio airable en direct) : aucune clé `pause`.
        let info = KEFParser.playerInfo(try fixture("player-live-radio"))
        let caps = try #require(info.capabilities)
        #expect(caps.pause == nil)
        #expect(caps.next == false)
        #expect(caps.previous == false)
        #expect(caps.seek == false)
        #expect(info.isLive)
        #expect(info.station?.title == "bel RTL Génération 80 90")
        #expect(info.station?.path == "airable:https://1234567890.airable.io/id/airable/radio/3881444309372455")
        #expect(!info.canGoNext && !info.canGoPrevious)
        #expect(TransportLogic.pauseStrategy(for: info) == .stop)
    }

    @Test func parsesTrackControls() {
        let caps = KEFParser.transportCapabilities(["pause": true, "next_": true, "previous": false, "seekTime": true])
        #expect(caps == TransportCapabilities(pause: true, next: true, previous: false, seek: true))
        // Variante tolérée « next ».
        #expect(KEFParser.transportCapabilities(["next": true])?.next == true)
        #expect(KEFParser.transportCapabilities(nil) == nil)
        #expect(KEFParser.transportCapabilities("pas un objet") == nil)
    }

    @Test func capabilitiesDriveSkipFlags() {
        var info = PlayerInfo(state: .playing, title: "T", serviceID: "spotify", durationMs: 1000)
        #expect(info.canGoNext && info.canGoPrevious) // sans controls : déduit (non live)
        info.capabilities = TransportCapabilities(pause: true, next: true, previous: false)
        #expect(info.canGoNext)
        #expect(!info.canGoPrevious)
    }

    // MARK: Pause ou stop

    @Test func pauseStrategy() {
        let live = PlayerInfo(state: .playing, isLive: true)
        #expect(TransportLogic.pauseStrategy(for: live) == .stop)
        let track = PlayerInfo(state: .playing, title: "T", durationMs: 1000)
        #expect(TransportLogic.pauseStrategy(for: track) == .pause)
        // L'enceinte annonce la pause : on la respecte même pour un flux live.
        var livePausable = live
        livePausable.capabilities = TransportCapabilities(pause: true)
        #expect(TransportLogic.pauseStrategy(for: livePausable) == .pause)
        // Pause explicitement refusée : arrêt.
        var trackNoPause = track
        trackNoPause.capabilities = TransportCapabilities(pause: false)
        #expect(TransportLogic.pauseStrategy(for: trackNoPause) == .stop)
        // Bloc controls sans clé pause, contenu non live : pause vérifiée.
        var trackUnknown = track
        trackUnknown.capabilities = TransportCapabilities(next: true)
        #expect(TransportLogic.pauseStrategy(for: trackUnknown) == .pause)
    }

    @Test func resumeAction() {
        let paused = PlayerInfo(state: .paused, title: "T", durationMs: 1000)
        #expect(TransportLogic.resumeAction(player: paused, stoppedStation: nil) == .toggle)
        // Radio arrêtée dont l'enceinte a gardé mediaRoles.
        let stoppedLive = PlayerInfo(state: .stopped, serviceID: KEFParser.airableService, isLive: true, station: Self.a)
        #expect(TransportLogic.resumeAction(player: stoppedLive, stoppedStation: nil) == .playStation(Self.a))
        // Lecteur vide après stop : station mémorisée.
        #expect(TransportLogic.resumeAction(player: .stopped, stoppedStation: Self.b) == .playStation(Self.b))
        // Rien à reprendre.
        #expect(TransportLogic.resumeAction(player: .stopped, stoppedStation: nil) == .toggle)
        // Un autre contenu (avec titre, non airable) a pris la place : bascule.
        let otherTrack = PlayerInfo(state: .stopped, title: "Autre", serviceID: "spotify", durationMs: 1000)
        #expect(TransportLogic.resumeAction(player: otherTrack, stoppedStation: Self.b) == .toggle)
    }

    // MARK: Zapping

    @Test func adjacentStationWrapsAround() {
        let list = [Self.a, Self.b, Self.c]
        #expect(TransportLogic.adjacentStation(.next, current: Self.a, in: list) == Self.b)
        #expect(TransportLogic.adjacentStation(.next, current: Self.c, in: list) == Self.a) // bouclage
        #expect(TransportLogic.adjacentStation(.previous, current: Self.a, in: list) == Self.c) // bouclage
        #expect(TransportLogic.adjacentStation(.previous, current: Self.b, in: list) == Self.a)
    }

    @Test func adjacentStationOutsideList() {
        let list = [Self.a, Self.b, Self.c]
        #expect(TransportLogic.adjacentStation(.next, current: Self.other, in: list) == Self.a)
        #expect(TransportLogic.adjacentStation(.previous, current: Self.other, in: list) == Self.c)
        #expect(TransportLogic.adjacentStation(.next, current: nil, in: list) == Self.a)
        // Même station désignée par son path (id différent).
        let samePath = Station(id: "autre-id", title: "B bis", path: Self.b.path)
        #expect(TransportLogic.adjacentStation(.next, current: samePath, in: list) == Self.c)
    }

    @Test func adjacentStationEdgeCases() {
        #expect(TransportLogic.adjacentStation(.next, current: Self.a, in: []) == nil)
        #expect(TransportLogic.adjacentStation(.next, current: Self.a, in: [Self.a]) == nil)
        #expect(TransportLogic.adjacentStation(.previous, current: Self.other, in: [Self.a]) == Self.a)
    }

    static func radioSnapshot(_ station: Station?) -> SpeakerSnapshot {
        SpeakerSnapshot(power: .on, source: .wifi,
                        player: PlayerInfo(state: .playing, title: "Titre", serviceID: KEFParser.airableService,
                                           isLive: true, station: station, canSkip: false,
                                           capabilities: TransportCapabilities(next: false, previous: false)))
    }

    @Test func skipPlanZapsFavorites() {
        let snap = Self.radioSnapshot(Self.b)
        let next = TransportLogic.skipPlan(.next, snapshot: snap, isOnline: true, station: Self.b,
                                           favorites: [Self.a, Self.b, Self.c], fallback: [Self.other])
        #expect(next.action == .station(Self.c))
        #expect(next.isRadio)
        #expect(next.label == "Radio suivante")
        #expect(next.help.contains("« C »"))
        let previous = TransportLogic.skipPlan(.previous, snapshot: snap, isOnline: true, station: Self.b,
                                               favorites: [Self.a, Self.b, Self.c], fallback: [])
        #expect(previous.action == .station(Self.a))
        #expect(previous.label == "Radio précédente")
    }

    @Test func skipPlanFallsBackToHistory() {
        let snap = Self.radioSnapshot(Self.other)
        let plan = TransportLogic.skipPlan(.next, snapshot: snap, isOnline: true, station: Self.other,
                                           favorites: [], fallback: [Self.a, Self.b])
        #expect(plan.action == .station(Self.a))
        #expect(plan.help.contains("radios récentes"))
        // Ni favori ni historique : désactivé, avec explication.
        let none = TransportLogic.skipPlan(.next, snapshot: snap, isOnline: true, station: Self.other,
                                           favorites: [], fallback: [])
        #expect(!none.isEnabled)
        #expect(none.isRadio)
        #expect(none.help.contains("aucune radio"))
    }

    @Test func skipPlanForTracks() {
        var snap = SpeakerSnapshot(power: .on, source: .wifi,
                                   player: PlayerInfo(state: .playing, title: "T", serviceID: "spotify", durationMs: 1000,
                                                      capabilities: TransportCapabilities(pause: true, next: true, previous: false)))
        let next = TransportLogic.skipPlan(.next, snapshot: snap, isOnline: true, station: nil, favorites: [Self.a], fallback: [])
        #expect(next.action == .track)
        #expect(next.label == "Piste suivante")
        let previous = TransportLogic.skipPlan(.previous, snapshot: snap, isOnline: true, station: nil, favorites: [Self.a], fallback: [])
        #expect(previous.action == .none)
        #expect(previous.help.contains("non disponible"))
        // Hors ligne ou en veille : désactivé.
        snap.power = .standby
        #expect(!TransportLogic.skipPlan(.next, snapshot: snap, isOnline: true, station: nil, favorites: [], fallback: []).isEnabled)
        snap.power = .on
        #expect(!TransportLogic.skipPlan(.next, snapshot: snap, isOnline: false, station: nil, favorites: [], fallback: []).isEnabled)
    }

    @Test func skipPlanNothingPlaying() {
        let snap = SpeakerSnapshot(power: .on, source: .wifi, player: .stopped)
        let plan = TransportLogic.skipPlan(.next, snapshot: snap, isOnline: true, station: nil, favorites: [Self.a], fallback: [])
        #expect(!plan.isEnabled)
        #expect(!plan.isRadio)
    }

    @Test func skipPlanOnPhysicalInputIgnoresStation() {
        // Entrée optique : pas de zapping de radio même si une station a été mémorisée.
        let snap = SpeakerSnapshot(power: .on, source: .optic, player: .stopped)
        let plan = TransportLogic.skipPlan(.next, snapshot: snap, isOnline: true, station: Self.a,
                                           favorites: [Self.a, Self.b], fallback: [])
        #expect(!plan.isRadio)
    }
}

/// Pause / reprise de bout en bout avec le faux client (qui, comme l'enceinte, ignore
/// « pause » sur une radio et oublie la station après « stop »).
@MainActor
@Suite("Transport : SpeakerStore + client démo", .serialized)
struct TransportStoreTests {
    func connected(_ client: any SpeakerClient) async throws -> SpeakerStore {
        let store = SpeakerStore(backoffMin: 0.05, backoffMax: 0.2, pollTimeout: 1)
        store.connect(client)
        try #require(await waitUntil { store.status == .online })
        return store
    }

    @Test func liveRadioStopsThenReplaysStation() async throws {
        let demo = DemoSpeakerClient(latency: .zero)
        let store = try await connected(demo)
        let station = DemoSpeakerClient.demoStations[2]
        await store.playStation(station)
        try #require(await waitUntil { store.snapshot.player.station == station && store.snapshot.isPlaying })

        await store.playPause()
        // Arrêt (pas pause), station conservée pour l'affichage et la reprise.
        #expect(store.snapshot.player.state == .stopped)
        #expect(store.stoppedStation == station)
        #expect(store.snapshot.player.station == station)
        #expect(store.activeStation == station)
        let demoPlayer = try await demo.playerInfo()
        #expect(demoPlayer.state == .stopped)
        #expect(demoPlayer.station == nil) // l'enceinte a « oublié » la radio

        await store.playPause()
        #expect(store.snapshot.isPlaying)
        #expect(store.stoppedStation == nil)
        try #require(await waitUntil { (try? await demo.playerInfo())?.station == station })
        #expect(try await demo.playerInfo().state == .playing)
        store.stop()
    }

    @Test func trackPausesAndResumes() async throws {
        let demo = DemoSpeakerClient(latency: .zero)
        let store = try await connected(demo)
        #expect(store.snapshot.player.isLive == false)
        await store.playPause()
        #expect(store.snapshot.player.state == .paused)
        #expect(try await demo.playerInfo().state == .paused)
        #expect(store.stoppedStation == nil)
        let frozen = store.estimatedPosition()
        try await Task.sleep(for: .milliseconds(120))
        #expect(store.estimatedPosition() == frozen) // position figée
        await store.playPause()
        #expect(store.snapshot.isPlaying)
        #expect(try await demo.playerInfo().state == .playing)
        store.stop()
    }

    @Test func pauseIgnoredFallsBackToStop() async throws {
        // Contenu présenté comme non live mais que l'enceinte refuse de mettre en pause.
        let client = PauseIgnoringClient()
        let store = try await connected(client)
        #expect(store.snapshot.isPlaying)
        await store.playPause()
        #expect(store.snapshot.player.state == .stopped)
        #expect(await client.commands == [.pause, .stop])
        store.stop()
    }
}

/// Client dont « pause » est sans effet (seul « stop » arrête la lecture).
actor PauseIgnoringClient: SpeakerClient {
    private(set) var commands: [PlayerControl] = []
    private var state: PlaybackState = .playing
    private var player: PlayerInfo { PlayerInfo(state: state, title: "Flux", serviceID: "autre", durationMs: nil) }
    func fetchState() async throws -> SpeakerSnapshot { SpeakerSnapshot(power: .on, source: .wifi, player: player) }
    func pollEvents(timeout: Int) async throws -> SpeakerEvents {
        try await Task.sleep(for: .milliseconds(200))
        return SpeakerEvents()
    }
    func resetEventQueue() async {}
    func playerInfo() async throws -> PlayerInfo { player }
    func setPower(on: Bool) async throws {}
    func setSource(_ source: SpeakerSource) async throws {}
    func setVolume(_ volume: Int) async throws {}
    func control(_ command: PlayerControl) async throws {
        commands.append(command)
        if command == .stop { state = .stopped }
    }
    func radioHistory() async throws -> [Station] { [] }
    func searchStations(_ query: String) async throws -> [Station] { [] }
    func playStation(path: String) async throws -> Station { throw KEFError.notAStation }
}
