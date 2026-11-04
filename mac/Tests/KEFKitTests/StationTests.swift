import Foundation
import Testing
@testable import KEFKit

@Suite("Stations airable")
struct StationTests {
    @Test func historyRowsAreStations() throws {
        let stations = KEFParser.stations(fromRows: try fixture("history"))
        #expect(stations.map(\.title) == ["RFM", "bel RTL Génération 80 90", "CHERIE FM"])
        let rfm = try #require(stations.first)
        #expect(rfm.id == "airable://airable/radio/6969495512079448")
        #expect(rfm.path == "airable:https://1234567890.airable.io/id/airable/radio/6969495512079448")
        #expect(rfm.icon == "http://static.airable.io/42/54/791051.png") // 256 px
        #expect(rfm.description == nil)
    }

    @Test func searchResultsSkipFilters() throws {
        let stations = KEFParser.stations(fromRows: try fixture("search-results"))
        // « Par localité / langue / genre » sont des filtres, pas des stations.
        #expect(!stations.contains { $0.title.hasPrefix("Par ") })
        #expect(stations.first?.title == "FIP")
        #expect(stations.allSatisfy { $0.path.contains(KEFParser.stationMarker) })
    }

    @Test func stationRowsFindAudio() throws {
        let rows = try #require(try fixture("station-rows")["rows"]?.arrayValue)
        #expect(rows.first?["type"]?.stringValue == "audio")
        // Les autres rows (« Groupe », « Podcasts »…) ne sont pas des stations.
        #expect(rows.dropFirst().compactMap(KEFParser.normalizeStation).isEmpty)
    }

    @Test func imageClosestTo256() {
        let row: JSONValue = ["images": ["images": [
            ["width": 64, "url": "a"], ["width": 300, "url": "b"], ["width": 1024, "url": "c"],
        ]], "icon": "z"]
        #expect(KEFParser.bestImage(row) == "b")
        #expect(KEFParser.bestImage(["icon": "z"]) == "z")
        #expect(KEFParser.bestImage(["icon": ""]) == nil)
    }

    @Test func rejectsNonStations() {
        #expect(KEFParser.normalizeStation(["path": "airable:https://x/airable/radios/filter/genres", "title": "Par genre"]) == nil)
        #expect(KEFParser.normalizeStation(["path": "airable:https://x/id/airable/radio/1"]) == nil)
        #expect(KEFParser.normalizeStation(nil) == nil)
        let demo = KEFParser.normalizeStation(["path": "demo:radio/1", "title": "Radio Cuivre"])
        #expect(demo?.id == "demo:radio/1") // id = path à défaut
    }

    @Test func sameStationByIdOrPath() {
        let a = Station(id: "1", title: "A", path: "p1")
        #expect(a.isSameStation(as: Station(id: "1", title: "B", path: "p2")))
        #expect(a.isSameStation(as: Station(id: "2", title: "A", path: "p1")))
        #expect(!a.isSameStation(as: Station(id: "2", title: "A", path: "p2")))
        #expect(!a.isSameStation(as: nil))
    }
}

@Suite("Client HTTP (transport simulé)")
struct HTTPClientTests {
    static let root = "airable:https://1234567890.airable.io/airable/radios"

    @Test func historyFollowsRedirect() async throws {
        let link = try fixtureData("radios-link")
        let history = try fixtureData("history")
        let session = MockURLProtocol.session(id: "history") { req in
            switch req.query("path") {
            case "airable:linkService_airable.radios": return (200, link)
            case Self.root: return (200, Data(#"{"rowsCount":0,"rows":[]}"#.utf8))
            case Self.root + "/history": return (200, history)
            default: return (404, Data())
            }
        }
        let client = KEFHTTPClient(host: "192.0.2.1", session: session)
        let stations = try await client.radioHistory()
        #expect(stations.count == 3)
        // La racine est mise en cache : un second appel ne redemande pas le lien.
        _ = try await client.radioHistory()
        let paths = MockURLProtocol.requests(id: "history").compactMap { $0.query("path") }
        #expect(paths.filter { $0 == "airable:linkService_airable.radios" }.count == 1)
        #expect(MockURLProtocol.requests(id: "history").allSatisfy { $0.query("roles") == "@all" })
    }

    @Test func searchUsesDiscoveredForm() async throws {
        let link = try fixtureData("radios-link")
        let form = try fixtureData("search-form")
        let submit = try fixtureData("search-submit")
        let results = try fixtureData("search-results")
        let resultsPath = #"airable:https://1234567890.airable.io/airable/radios/search\?q\=fip"#
        let session = MockURLProtocol.session(id: "search") { req in
            if req.url?.path == "/api/setData" {
                let body = req.jsonBody
                if body?["path"]?.stringValue == "airable:form7:submit" { return (200, submit) }
                return (200, Data("true".utf8))
            }
            switch req.query("path") {
            case "airable:linkService_airable.radios": return (200, link)
            case Self.root: return (200, Data(#"{"rowsCount":0,"rows":[]}"#.utf8))
            case Self.root + "/search": return (200, Data(#"{"rows":[],"rowsRedirect":"airable:form7"}"#.utf8))
            case "airable:form7": return (200, form)
            case resultsPath: return (200, results)
            default: return (404, Data())
            }
        }
        let client = KEFHTTPClient(host: "192.0.2.1", session: session)
        let stations = try await client.searchStations("fip")
        #expect(stations.first?.title == "FIP")
        let sets = MockURLProtocol.requests(id: "search").filter { $0.url?.path == "/api/setData" }.compactMap(\.jsonBody)
        #expect(sets.count == 2)
        #expect(sets[0] == ["path": "airable:form7:q", "role": "value", "value": ["type": "string_", "string_": "fip"]])
        #expect(sets[1] == ["path": "airable:form7:submit", "role": "activate", "value": [:]])
    }

    @Test func playStationSendsAudioRow() async throws {
        let stationRows = try fixtureData("station-rows")
        let path = "airable:https://1234567890.airable.io/id/airable/radio/8559024957008661"
        let session = MockURLProtocol.session(id: "play") { req in
            if req.url?.path == "/api/setData" { return (200, Data("true".utf8)) }
            return req.query("path") == path ? (200, stationRows) : (404, Data())
        }
        let client = KEFHTTPClient(host: "192.0.2.1", session: session)
        let station = try await client.playStation(path: path)
        #expect(station.title == "FIP")
        let body = try #require(MockURLProtocol.requests(id: "play").first { $0.url?.path == "/api/setData" }?.jsonBody)
        #expect(body["path"] == "player:player/control")
        #expect(body["role"] == "activate")
        #expect(body["value"]?["control"] == "play")
        #expect(body["value"]?["mediaRoles"]?["type"] == "audio")
        #expect(body["value"]?["mediaRoles"]?["mediaData"]?["resources"]?[0]?["bitRate"] == .int(192000))

        await #expect(throws: KEFError.notAStation) { try await client.playStation(path: "demo:radio/1") }
    }

    @Test func fetchStateAndPolling() async throws {
        let values: [String: String] = [
            "settings:/kef/host/speakerStatus": #"[{"kefSpeakerStatus":"standby","type":"kefSpeakerStatus"}]"#,
            "settings:/releasetext": #"[{"string_":"LS50WII_V41192","type":"string_"}]"#,
            "settings:/system/primaryMacAddress": #"[{"string_":"00:11:22:33:44:55","type":"string_"}]"#,
            "settings:/deviceName": #"[{"string_":"LS50 Wireless II-a1b2c3","type":"string_"}]"#,
            "settings:/kef/play/physicalSource": #"[{"kefPhysicalSource":"standby","type":"kefPhysicalSource"}]"#,
            "player:volume": #"[{"type":"i32_","i32_":30}]"#,
            "settings:/mediaPlayer/mute": #"[{"bool_":false,"type":"bool_"}]"#,
            "player:player/data": #"[{"mediaRoles":{},"trackRoles":{},"state":"stopped"}]"#,
        ]
        let polls = Counter()
        let session = MockURLProtocol.session(id: "state") { req in
            switch req.url?.path {
            case "/api/getData":
                if let v = values[req.query("path") ?? ""] { return (200, Data(v.utf8)) }
                return (500, Data())
            case "/api/event/modifyQueue":
                return (200, Data(#""{08a1a242-318a-48b6-8aa2-2638bfca6f97}""#.utf8))
            case "/api/event/pollQueue":
                // 1er appel : un événement ; 2e : file expirée (« Unknown queue id! »).
                if polls.next() == 0 {
                    return (200, Data(#"[{"path":"player:volume","itemValue":{"type":"i32_","i32_":31}}]"#.utf8))
                }
                return (400, Data("Unknown queue id!".utf8))
            default:
                return (404, Data())
            }
        }
        let client = KEFHTTPClient(host: "192.0.2.1", session: session)
        let snap = try await client.fetchState()
        #expect(snap.power == .standby)
        #expect(snap.source == nil)
        #expect(snap.model == "LS50WII")
        #expect(snap.modelLabel == "LS50 Wireless II")
        #expect(snap.firmware == "V41192")
        #expect(snap.volume == 30)
        #expect(snap.name == "LS50 Wireless II-a1b2c3")
        #expect(snap.sources.count == 6)

        let ev = try await client.pollEvents(timeout: 1)
        #expect(ev.volume == 31)
        let expired = try await client.pollEvents(timeout: 1)
        #expect(expired.isEmpty)
        let reqs = MockURLProtocol.requests(id: "state")
        let poll = try #require(reqs.first { $0.url?.path == "/api/event/pollQueue" })
        #expect(poll.query("queueId") == "{08a1a242-318a-48b6-8aa2-2638bfca6f97}")
        let subscribe = try #require(reqs.first { $0.url?.path == "/api/event/modifyQueue" }?.jsonBody)
        let paths = subscribe["subscribe"]?.arrayValue?.compactMap { $0["path"]?.stringValue } ?? []
        #expect(paths.contains("player:player/data/playTime"))
        // Après expiration, le prochain poll se réabonne.
        _ = try? await client.pollEvents(timeout: 1)
        #expect(MockURLProtocol.requests(id: "state").filter { $0.url?.path == "/api/event/modifyQueue" }.count == 2)
    }

    @Test func commandsPayloads() async throws {
        let session = MockURLProtocol.session(id: "commands") { _ in (200, Data("true".utf8)) }
        let client = KEFHTTPClient(host: "192.0.2.1", session: session)
        try await client.setVolume(140)
        try await client.setSource(.optic)
        try await client.setPower(on: false)
        try await client.control(.next)
        let bodies = MockURLProtocol.requests(id: "commands").compactMap(\.jsonBody)
        #expect(bodies[0] == ["path": "player:volume", "roles": "value", "value": ["type": "i32_", "i32_": 100]])
        #expect(bodies[1]["value"]?["kefPhysicalSource"] == "optic")
        #expect(bodies[2]["value"]?["kefPhysicalSource"] == "standby")
        #expect(bodies[3] == ["path": "player:player/control", "roles": "activate", "value": ["control": "next"]])
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}
