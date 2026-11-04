import Foundation
import Testing
@testable import KEFKit

@Suite("Analyse des réponses de l'enceinte")
struct ParserTests {
    @Test func jsonValueRoundTripPreservesIntegers() throws {
        let raw = #"{"bitRate":192000,"ratio":0.5,"ok":true,"n":null,"s":"a\\?q\\=fip","a":[1,"x"]}"#
        let value = try JSONValue.parse(Data(raw.utf8))
        #expect(value["bitRate"] == .int(192000))
        #expect(value["ratio"] == .double(0.5))
        #expect(value["ok"]?.boolValue == true)
        #expect(value["s"]?.stringValue == #"a\?q\=fip"#)
        let back = String(decoding: try value.encoded(), as: UTF8.self)
        #expect(back.contains(#""bitRate":192000"#))
    }

    @Test func modelAndFirmwareFromReleaseText() {
        let split = KEFParser.splitRelease("LS50WII_V41192")
        #expect(split.model == "LS50WII")
        #expect(split.firmware == "V41192")
        #expect(KEFParser.normalizeModel("LS50W2") == "LS50WII")
        #expect(KEFParser.normalizeModel("LSX2LT") == "LSXIILT")
        #expect(KEFParser.normalizeModel("LSXII") == "LSXII")
        #expect(KEFParser.normalizeModel("LS60") == "LS60")
        #expect(KEFParser.sources(forModel: "LSXIILT") == [.wifi, .bluetooth, .tv, .optic, .usb])
    }

    @Test func sourceAliases() {
        #expect(SpeakerSource.parse("optical") == .optic)
        #expect(SpeakerSource.parse("Coax") == .coaxial)
        #expect(SpeakerSource.parse("aux") == .analog)
        #expect(SpeakerSource.parse("standby") == nil)
    }

    @Test func stoppedPlayerData() throws {
        // Réponse réelle de getData player:player/data, enceinte en veille.
        let raw = #"[{"error":"","keepActive":false,"mediaRoles":{},"streamerError":{},"playId":{"timestamp":356023647,"systemMemberId":"kef_one-x"},"trackRoles":{},"state":"stopped"}]"#
        let info = KEFParser.playerInfo(KEFParser.firstItem(try JSONValue.parse(Data(raw.utf8))))
        #expect(info.state == .stopped)
        #expect(info.title == nil)
        #expect(info.station == nil)
        #expect(info.durationMs == nil)
    }

    @Test func trackPlayerData() {
        let data: JSONValue = [
            "state": "playing",
            "trackRoles": [
                "title": "Uni-Q Sunrise",
                "icon": "https://i.scdn.co/image/abc",
                "mediaData": ["metaData": ["artist": "The Coaxials", "album": "Concentric", "serviceID": "spotify"]],
            ],
            "status": ["duration": 214000, "playSpeed": 1],
            "controls": ["pause": true, "next_": true, "previous": true],
        ]
        let info = KEFParser.playerInfo(data)
        #expect(info.state == .playing)
        #expect(info.title == "Uni-Q Sunrise")
        #expect(info.artist == "The Coaxials")
        #expect(info.album == "Concentric")
        #expect(info.coverURL == "https://i.scdn.co/image/abc")
        #expect(info.durationMs == 214000)
        #expect(!info.isLive)
        #expect(info.canSkip)
    }

    @Test func airableRadioPlayerData() throws {
        // Forme d'une radio airable en cours : titre diffusé dans trackRoles, station dans mediaRoles.
        let audioRow = try #require(try fixture("station-rows")["rows"]?[0])
        let data: JSONValue = [
            "state": "playing",
            "trackRoles": [
                "title": "Nina Simone - Feeling Good",
                "icon": "http://static.airable.io/79/52/231493.png",
                "mediaData": ["metaData": ["serviceID": "airableRadios", "live": true, "artist": "FIP"], "resources": []],
            ],
            "mediaRoles": audioRow,
            "status": [:],
            "controls": ["pause": true, "next_": false, "previous": false],
        ]
        let info = KEFParser.playerInfo(data)
        #expect(info.isAirableRadio)
        #expect(info.isLive)
        #expect(!info.canSkip)
        #expect(info.durationMs == nil)
        let station = try #require(info.station)
        #expect(station.title == "FIP")
        #expect(station.id == "airable://airable/radio/8559024957008661")
        #expect(station.description == "Toutes les musiques, une seule radio") // slogan
        #expect(station.icon == "http://static.airable.io/58/32/274991.png")   // image 256 px
    }

    @Test func pollQueueEvents() throws {
        // Forme renvoyée par /api/event/pollQueue (cf. pykefcontrol.parse_events).
        let raw = """
        [
          {"path":"player:volume","itemType":"itemWithValue","itemValue":{"type":"i32_","i32_":25}},
          {"path":"player:volume","itemType":"itemWithValue","itemValue":{"type":"i32_","i32_":27}},
          {"path":"settings:/kef/play/physicalSource","itemValue":{"type":"kefPhysicalSource","kefPhysicalSource":"tv"}},
          {"path":"settings:/kef/host/speakerStatus","itemValue":{"type":"kefSpeakerStatus","kefSpeakerStatus":"powerOn"}},
          {"path":"settings:/mediaPlayer/mute","itemValue":{"type":"bool_","bool_":true}},
          {"path":"player:player/data/playTime","itemValue":{"type":"i64_","i64_":61234}},
          {"path":"settings:/deviceName","itemValue":{"type":"string_","string_":"Salon"}},
          {"path":"kef:eqProfile","itemValue":{"type":"x"}},
          {"path":"player:player/data","itemValue":{"state":"paused","trackRoles":{"title":"T"},"status":{"duration":1000}}}
        ]
        """
        let ev = KEFParser.events(try JSONValue.parse(Data(raw.utf8)))
        #expect(ev.volume == 27) // dernière valeur
        #expect(ev.source == "tv")
        #expect(ev.power == .on)
        #expect(ev.mute == true)
        #expect(ev.positionMs == 61234)
        #expect(ev.deviceName == "Salon")
        #expect(ev.player?.state == .paused)
        #expect(ev.player?.durationMs == 1000)
        #expect(KEFParser.events([]).isEmpty)
    }

    @Test func hostValidation() throws {
        #expect(try HostValidator.normalize(" http://192.168.1.50/ ") == "192.168.1.50")
        #expect(try HostValidator.normalize("kef_one-001122a1b2c3.local") == "kef_one-001122a1b2c3.local")
        #expect(try HostValidator.normalize("10.0.0.2:8080") == "10.0.0.2:8080")
        #expect(throws: KEFError.self) { try HostValidator.normalize("") }
        #expect(throws: KEFError.self) { try HostValidator.normalize("a b") }
    }

    @Test func localNetworkDeniedIsExplained() {
        // Forme observée quand macOS bloque l'accès au réseau local (journal : « Local network prohibited »).
        let denied = URLError(.notConnectedToInternet, userInfo: [
            "_NSURLErrorNWPathKey": "unsatisfied (Local network prohibited), interface: en1[802.11], ipv4",
        ])
        #expect(isLocalNetworkDenied(denied))
        #expect(describe(denied) == localNetworkDeniedMessage)
        #expect(describe(URLError(.notConnectedToInternet)) == "Réseau indisponible")
    }

    @Test func queryEncodingEscapesAirablePaths() {
        let q = KEFHTTPClient.encodeQuery([("path", #"airable:https://x.airable.io/airable/radios/search\?q\=fip"#)])
        #expect(q == "path=airable%3Ahttps%3A%2F%2Fx.airable.io%2Fairable%2Fradios%2Fsearch%5C%3Fq%5C%3Dfip")
    }

    @Test func discoveryFilter() {
        // TXT réels de la LS50 Wireless II (_airplay._tcp et _raop._tcp).
        let airplay = ["manufacturer": "KEF", "model": "LS50 Wireless II", "deviceid": "00:11:22:33:44:55"]
        #expect(KEFDiscoveryFilter.isKEF(name: "LS50 Wireless II-a1b2c3", txt: airplay))
        #expect(KEFDiscoveryFilter.model(txt: airplay) == "LS50 Wireless II")
        let raop = ["am": "LS50 Wireless II", "md": "0,1,2"]
        #expect(KEFDiscoveryFilter.friendlyName(serviceName: "001122A1B2C3@LS50 Wireless II-a1b2c3", txt: raop)
            == "LS50 Wireless II-a1b2c3")
        #expect(KEFDiscoveryFilter.model(txt: raop) == "LS50 Wireless II")
        #expect(!KEFDiscoveryFilter.isKEF(name: "iMac de Céline", txt: ["model": "iMac21,1"]))
        #expect(KEFDiscoveryFilter.friendlyName(serviceName: "LS50-Wireless-II-7c1b", txt: ["fn": "LS50 Wireless II-a1b2c3"])
            == "LS50 Wireless II-a1b2c3")
    }
}
