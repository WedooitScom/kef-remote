import Foundation
import Testing
@testable import KEFKit

/// Client qui échoue toujours (enceinte injoignable), pour tester le mode hors ligne.
actor FailingClient: SpeakerClient {
    private(set) var fetchCount = 0
    private(set) var resets = 0
    func fetchState() async throws -> SpeakerSnapshot {
        fetchCount += 1
        throw URLError(.cannotConnectToHost)
    }
    func pollEvents(timeout: Int) async throws -> SpeakerEvents { throw URLError(.timedOut) }
    func resetEventQueue() async { resets += 1 }
    func playerInfo() async throws -> PlayerInfo { throw URLError(.timedOut) }
    func setPower(on: Bool) async throws { throw URLError(.timedOut) }
    func setSource(_ source: SpeakerSource) async throws { throw URLError(.timedOut) }
    func setVolume(_ volume: Int) async throws { throw URLError(.timedOut) }
    func control(_ command: PlayerControl) async throws { throw URLError(.timedOut) }
    func radioHistory() async throws -> [Station] { [] }
    func searchStations(_ query: String) async throws -> [Station] { [] }
    func playStation(path: String) async throws -> Station { throw URLError(.timedOut) }
}

/// Client démo dont les commandes de source échouent (pour tester l'annulation de l'optimisme).
actor RejectingSourceClient: SpeakerClient {
    let demo = DemoSpeakerClient(latency: .zero)
    func fetchState() async throws -> SpeakerSnapshot { try await demo.fetchState() }
    func pollEvents(timeout: Int) async throws -> SpeakerEvents { try await demo.pollEvents(timeout: timeout) }
    func resetEventQueue() async {}
    func playerInfo() async throws -> PlayerInfo { try await demo.playerInfo() }
    func setPower(on: Bool) async throws { try await demo.setPower(on: on) }
    func setSource(_ source: SpeakerSource) async throws {
        try await Task.sleep(for: .milliseconds(50))
        throw KEFError.http(500, "refus")
    }
    func setVolume(_ volume: Int) async throws { try await demo.setVolume(volume) }
    func control(_ command: PlayerControl) async throws { try await demo.control(command) }
    func radioHistory() async throws -> [Station] { try await demo.radioHistory() }
    func searchStations(_ query: String) async throws -> [Station] { try await demo.searchStations(query) }
    func playStation(path: String) async throws -> Station { try await demo.playStation(path: path) }
}

@MainActor
@Suite("Logique d'état (faux client)", .serialized)
struct SpeakerStoreTests {
    func connected(_ client: any SpeakerClient = DemoSpeakerClient(latency: .zero)) async throws -> SpeakerStore {
        let store = SpeakerStore(backoffMin: 0.05, backoffMax: 0.2, pollTimeout: 1)
        store.connect(client)
        #expect(store.status == .connecting)
        try #require(await waitUntil { store.status == .online })
        return store
    }

    @Test func notConfigured() {
        let store = SpeakerStore()
        store.connect(nil)
        #expect(store.status == .notConfigured)
        store.setVolume(10)
        #expect(store.commandError == "Aucune enceinte configurée")
    }

    @Test func initialStateFromDemo() async throws {
        let store = try await connected()
        #expect(store.snapshot.name == "Salon (démo)")
        #expect(store.snapshot.power == .on)
        #expect(store.snapshot.source == .wifi)
        #expect(store.snapshot.volume == 32)
        #expect(store.snapshot.player.title == "Uni-Q Sunrise")
        #expect(store.snapshot.player.durationMs == 214_000)
        let pos = try #require(store.estimatedPosition())
        #expect(pos >= 42_000)
        store.stop()
    }

    @Test func optimisticVolumeThenReconciled() async throws {
        let demo = DemoSpeakerClient(latency: .milliseconds(30))
        let store = try await connected(demo)
        store.setVolume(55)
        #expect(store.snapshot.volume == 55) // immédiat
        store.setVolume(57)
        store.setVolume(60)
        #expect(store.snapshot.volume == 60)
        // L'enceinte (simulée) finit avec la dernière valeur demandée.
        #expect(await waitUntil { await demo.fetchStateVolume() == 60 })
        #expect(store.snapshot.volume == 60)
        store.stop()
    }

    @Test func muteRestoresLastVolume() async throws {
        let store = try await connected()
        store.toggleMute()
        #expect(store.snapshot.volume == 0)
        #expect(store.snapshot.isMuted)
        store.toggleMute()
        #expect(store.snapshot.volume == 32)
        #expect(!store.snapshot.isMuted)
        store.stop()
    }

    @Test func playPauseAndEvents() async throws {
        let store = try await connected()
        await store.playPause()
        #expect(store.snapshot.player.state == .paused)
        let frozen = store.estimatedPosition()
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.estimatedPosition() == frozen) // la progression est figée en pause
        await store.nextTrack()
        #expect(await waitUntil { store.snapshot.player.title == "Tangerine Waveguide" })
        #expect(store.snapshot.player.state == .playing)
        store.stop()
    }

    @Test func powerAndSource() async throws {
        let store = try await connected()
        await store.setPower(on: false)
        #expect(store.snapshot.power == .standby)
        #expect(!store.snapshot.isPlaying)
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.snapshot.power == .standby) // confirmé par les événements
        await store.selectSource(.tv)
        #expect(store.snapshot.power == .on)
        #expect(await waitUntil { store.snapshot.source == .tv })
        #expect(store.snapshot.player.state == .stopped) // pas de lecteur hors Wi‑Fi
        store.stop()
    }

    @Test func failedCommandRollsBack() async throws {
        let store = try await connected(RejectingSourceClient())
        await store.selectSource(.optic)
        #expect(store.snapshot.source == .wifi)
        #expect(store.commandError?.hasPrefix("Commande refusée") == true)
        store.stop()
    }

    @Test func playStationFromStandbyWakesOnWifi() async throws {
        let store = try await connected(DemoSpeakerClient(latency: .zero, poweredOn: false))
        #expect(store.snapshot.power == .standby)
        let stations = try await store.searchStations("cuivre")
        #expect(stations.map(\.title) == ["Radio Cuivre", "Radio Cuivre Groove"])
        await store.playStation(stations[0])
        #expect(store.snapshot.power == .on)
        #expect(store.snapshot.source == .wifi)
        #expect(store.snapshot.currentStation?.id == stations[0].id)
        #expect(await waitUntil { store.snapshot.player.title == "Brass Tweeter Blues" })
        #expect(store.snapshot.player.isLive)
        #expect(store.snapshot.player.durationMs == nil)
        #expect(store.loadingStationID == nil)
        let history = try await store.radioHistory()
        #expect(history.first?.title == "Radio Cuivre")
        store.stop()
    }

    @Test func offlineWithBackoffAndRetry() async throws {
        let failing = FailingClient()
        let store = SpeakerStore(backoffMin: 0.05, backoffMax: 0.1, pollTimeout: 1)
        store.connect(failing)
        #expect(await waitUntil {
            if case .offline = store.status { return true }
            return false
        })
        #expect(store.status == .offline("Enceinte injoignable"))
        // Le client retente régulièrement et réinitialise la file d'événements.
        #expect(await waitUntil { await failing.fetchCount >= 3 })
        #expect(await failing.resets >= 2)
        await store.playPause()
        #expect(store.commandError == "Enceinte hors ligne")
        // Bascule vers un client joignable : l'état repasse en ligne.
        store.connect(DemoSpeakerClient(latency: .zero))
        #expect(await waitUntil { store.status == .online })
        store.stop()
    }
}

extension DemoSpeakerClient {
    func fetchStateVolume() async -> Int { (try? await fetchState().volume) ?? -1 }
}

/// `waitUntil` avec une condition asynchrone.
@MainActor
func waitUntil(timeout: Double = 5, _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
