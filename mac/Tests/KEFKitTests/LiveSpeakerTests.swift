import Foundation
import Testing
@testable import KEFKit

/// Tests contre une vraie enceinte, désactivés par défaut.
///
///     KEF_LIVE_HOST=192.168.1.50 swift test --filter LiveSpeakerTests
///
/// Lectures uniquement (état, événements, historique, recherche, explorateur). La seule commande
/// envoyée est la relecture de la station airable *déjà en cours*, et seulement si une
/// radio airable joue réellement. Volume, source et alimentation ne sont jamais modifiés.
@Suite("Enceinte réelle (KEF_LIVE_HOST)", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["KEF_LIVE_HOST"] != nil))
struct LiveSpeakerTests {
    let client = KEFHTTPClient(host: ProcessInfo.processInfo.environment["KEF_LIVE_HOST"] ?? "")

    @Test func probeAndState() async throws {
        let probe = try await KEFHTTPClient.probe(host: client.host)
        print("[live] sonde : \(probe.name) — \(probe.release)")
        let snap = try await client.fetchState()
        print("[live] état : power=\(snap.power) source=\(snap.source?.rawValue ?? "-") volume=\(snap.volume) "
            + "modèle=\(snap.modelLabel ?? "?") fw=\(snap.firmware ?? "?") lecteur=\(snap.player.state) "
            + "titre=\(snap.player.title ?? "-") station=\(snap.player.station?.title ?? "-")")
        #expect(snap.model != nil)
        #expect(!snap.sources.isEmpty)
    }

    @Test func pollEventsLongPolling() async throws {
        let start = Date()
        let events = try await client.pollEvents(timeout: 3)
        let elapsed = Date().timeIntervalSince(start)
        print("[live] pollQueue (3 s) : \(String(format: "%.1f", elapsed)) s, vide=\(events.isEmpty) \(events)")
        #expect(elapsed < 8)
        // Second appel sur la même file.
        _ = try await client.pollEvents(timeout: 1)
    }

    @Test func radioHistoryAndSearch() async throws {
        let history = try await client.radioHistory()
        print("[live] historique : \(history.map(\.title))")
        let results = try await client.searchStations("fip")
        print("[live] recherche « fip » : \(results.prefix(6).map(\.title))")
        #expect(results.allSatisfy { $0.path.contains(KEFParser.stationMarker) })
        #expect(!results.isEmpty)
    }

    @Test func explorerBrowsing() async throws {
        let genres = try await client.browseRadios(.directory(.genres), from: 0, count: 50)
        print("[live] genres : \(genres.items.count)/\(genres.totalCount ?? -1) — \(genres.items.prefix(6).map(\.title))")
        #expect(genres.items.count > 10)
        let leaf = try #require(genres.items.first { $0.path.contains("filter\\?g") })
        let first = try await client.browseRadios(.path(leaf.path), from: 0, count: 50)
        #expect(first.items.compactMap(\.facet).count == 3)
        let second = try await client.browseRadios(.path(first.path), from: first.nextOffset, count: 50)
        print("[live] « \(leaf.title) » : \(first.totalCount ?? -1) rows, page 2 = \(second.items.count) stations")
        #expect(second.items.allSatisfy { $0.station != nil })
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
        for directory in RadioDirectory.shelves {
            let page = try await client.browseRadios(.directory(directory), from: 0, count: 3)
            print("[live] \(directory.title) : \(page.totalCount ?? -1) — \(page.items.map(\.title))")
            #expect(!page.items.isEmpty)
        }
    }

    @Test func replayCurrentAirableStationOnlyIfPlaying() async throws {
        let snap = try await client.fetchState()
        guard snap.power == .on, snap.source == .wifi, snap.player.state == .playing,
              let station = snap.player.station else {
            print("[live] aucune radio airable en lecture (lecteur \(snap.player.state)) : aucune commande envoyée")
            return
        }
        print("[live] relecture de la station en cours : \(station.title)")
        let replayed = try await client.playStation(path: station.path)
        #expect(replayed.isSameStation(as: station))
    }
}

/// Un cycle pause → reprise sur la radio en cours, via `SpeakerStore` (même chemin que l'app).
/// Double garde : `KEF_LIVE_HOST` **et** `KEF_LIVE_PAUSE=1`. Ne fait rien si aucune radio
/// airable ne joue ; à la fin, la même station doit rejouer (sinon elle est relancée).
///
///     KEF_LIVE_HOST=192.168.1.50 KEF_LIVE_PAUSE=1 swift test --filter LivePauseTests
@MainActor
@Suite("Enceinte réelle : pause / reprise d'une radio (KEF_LIVE_PAUSE=1)", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["KEF_LIVE_HOST"] != nil
           && ProcessInfo.processInfo.environment["KEF_LIVE_PAUSE"] == "1"))
struct LivePauseTests {
    let host = ProcessInfo.processInfo.environment["KEF_LIVE_HOST"] ?? ""

    /// État brut lu par getData (sans passer par le store).
    func raw(_ client: KEFHTTPClient) async throws -> String {
        let data = try await client.getData("player:player/data")
        let roles = data["mediaRoles"]
        let keys = data["controls"]?.objectValue.map { $0.keys.sorted().joined(separator: ",") } ?? "-"
        return "state=\(data["state"]?.stringValue ?? "?") mediaRoles.title=\(roles?["title"]?.stringValue ?? "∅") "
            + "path=\(roles?["path"]?.stringValue ?? "∅") controls=[\(keys)]"
    }

    @Test func pauseThenResumeCurrentRadio() async throws {
        let probe = KEFHTTPClient(host: host)
        let before = try await probe.fetchState()
        guard before.power == .on, before.source == .wifi, before.player.state == .playing,
              let station = before.player.station else {
            print("[live-pause] aucune radio airable en lecture : aucune commande envoyée")
            return
        }
        print("[live-pause] départ : \(station.title) volume=\(before.volume) — \(try await raw(probe))")

        let store = SpeakerStore(pollTimeout: 2)
        store.connect(KEFHTTPClient(host: host))
        try #require(await waitUntil(timeout: 10) { store.status == .online && store.snapshot.isPlaying })
        print("[live-pause] stratégie : \(TransportLogic.pauseStrategy(for: store.snapshot.player))")

        await store.playPause() // pause
        print("[live-pause] après pause : store=\(store.snapshot.player.state) erreur=\(store.commandError ?? "-")")
        try await Task.sleep(for: .seconds(2))
        let paused = try await raw(probe)
        print("[live-pause] getData après pause : \(paused)")
        #expect(paused.hasPrefix("state=stopped") || paused.hasPrefix("state=paused"))

        await store.playPause() // reprise
        print("[live-pause] après reprise : store=\(store.snapshot.player.state) erreur=\(store.commandError ?? "-")")
        var after = try await probe.fetchState()
        for _ in 0..<10 where after.player.state != .playing {
            try await Task.sleep(for: .seconds(1))
            after = try await probe.fetchState()
        }
        print("[live-pause] getData après reprise : \(try await raw(probe))")
        if after.player.state != .playing || !(after.player.station?.isSameStation(as: station) ?? false) {
            // Filet de sécurité : l'enceinte doit rejouer la même station.
            print("[live-pause] reprise non confirmée : relance directe de \(station.title)")
            try await probe.playStation(path: station.path)
            try await Task.sleep(for: .seconds(3))
            after = try await probe.fetchState()
        }
        store.stop()
        print("[live-pause] fin : \(after.player.state) \(after.player.station?.title ?? "-") volume=\(after.volume) source=\(after.source?.rawValue ?? "-")")
        #expect(after.player.state == .playing)
        #expect(after.player.station?.isSameStation(as: station) == true)
        #expect(after.volume == before.volume)
    }
}
