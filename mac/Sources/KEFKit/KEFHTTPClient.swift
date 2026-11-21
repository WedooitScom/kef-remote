import Foundation

/// Client HTTP parlant directement à l'enceinte (API NSDK StreamUnlimited).
///
/// Points d'entrée utilisés (cf. pykefcontrol `kef_connector.py` et `app/radio.py`) :
/// - `GET  /api/getData?path=…&roles=value`
/// - `POST /api/setData` (JSON `{path, roles|role, value}`)
/// - `POST /api/event/modifyQueue` puis `GET /api/event/pollQueue?queueId={…}&timeout=n`
/// - `GET  /api/getRows?path=…&roles=@all&from=0&to=n` (navigation airable, avec `rowsRedirect`)
public actor KEFHTTPClient: SpeakerClient {
    public nonisolated let host: String
    private let session: URLSession

    private var queueID: String?
    private var lastPolled: Date?
    private var cachedModel: (model: String, firmware: String?, mac: String?)?
    private var radiosRoot: String?
    /// Le formulaire de recherche airable est un état partagé côté enceinte : une recherche à la fois.
    private var searchTail: Task<Void, Never>?

    static let radiosLink = "airable:linkService_airable.radios"
    static let maxRedirects = 4
    static let searchLimit = 60
    /// Au-delà, l'enceinte a pu oublier la file : on se réabonne (même seuil que pykefcontrol).
    static let queueMaxIdle: TimeInterval = 50

    public init(host: String, session: URLSession? = nil) {
        self.host = host
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpMaximumConnectionsPerHost = 4
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - HTTP brut

    /// Encodage strict des paramètres (les paths airable contiennent `\?`, `\=`, `:`…).
    static func encodeQuery(_ items: [(String, String)]) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return items.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    private func url(_ endpoint: String, _ items: [(String, String)] = []) throws -> URL {
        let query = items.isEmpty ? "" : "?" + Self.encodeQuery(items)
        guard let url = URL(string: "http://\(host)\(endpoint)\(query)") else { throw KEFError.invalidHost(host) }
        return url
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KEFError.invalidResponse("pas de réponse HTTP") }
        guard (200..<300).contains(http.statusCode) else {
            throw KEFError.http(http.statusCode, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    private func getJSON(_ endpoint: String, _ items: [(String, String)], timeout: TimeInterval? = nil) async throws -> JSONValue {
        var request = URLRequest(url: try url(endpoint, items))
        if let timeout { request.timeoutInterval = timeout }
        let data = try await perform(request)
        do { return try JSONValue.parse(data) } catch { throw KEFError.invalidResponse(endpoint) }
    }

    private func postJSON(_ endpoint: String, _ body: JSONValue) async throws -> JSONValue? {
        var request = URLRequest(url: try url(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body.encoded()
        let data = try await perform(request)
        if data.isEmpty { return nil }
        return try? JSONValue.parse(data)
    }

    /// `getData` → premier élément du tableau renvoyé.
    public func getData(_ path: String, roles: String = "value") async throws -> JSONValue {
        let value = try await getJSON("/api/getData", [("path", path), ("roles", roles)])
        guard let first = KEFParser.firstItem(value) else { throw KEFError.invalidResponse(path) }
        return first
    }

    /// `setData`. pykefcontrol envoie la clé `roles`, le code radio validé envoie `role` :
    /// on reproduit chaque variante telle qu'elle a été vérifiée sur l'enceinte.
    @discardableResult
    func setData(_ path: String, role: String, value: JSONValue, roleKey: String = "roles") async throws -> JSONValue? {
        try await postJSON("/api/setData", .object(["path": .string(path), roleKey: .string(role), "value": value]))
    }

    /// `getRows` en suivant les redirections ; renvoie la réponse et le path final.
    /// `to` est inclusif côté enceinte (`from=0&to=2` → 3 rows) : on demande `from…from+count-1`.
    func getRows(_ path: String, from: Int = 0, count: Int = 50) async throws -> (response: JSONValue, path: String) {
        var current = path
        for _ in 0...Self.maxRedirects {
            let data = try await getJSON("/api/getRows", [
                ("path", current), ("roles", "@all"), ("from", String(from)), ("to", String(from + max(1, count) - 1)),
            ])
            guard data.objectValue != nil else { throw KEFError.invalidResponse("getRows") }
            let rows = data["rows"]?.arrayValue ?? []
            if let redirect = data["rowsRedirect"]?.nonEmptyString, rows.isEmpty {
                current = redirect
                continue
            }
            return (data, current)
        }
        throw KEFError.tooManyRedirects
    }

    // MARK: - Sonde (réglages)

    /// Vérifie qu'un hôte répond comme une enceinte KEF : renvoie son nom et son « release text ».
    public static func probe(host: String, timeout: TimeInterval = 4) async throws -> (name: String, release: String) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let client = KEFHTTPClient(host: host, session: URLSession(configuration: config))
        async let name = client.getData("settings:/deviceName")
        async let release = client.getData("settings:/releasetext")
        guard let n = try await name["string_"]?.stringValue, let r = try await release["string_"]?.stringValue else {
            throw KEFError.invalidResponse("probe")
        }
        return (n, r)
    }

    // MARK: - État

    public func fetchState() async throws -> SpeakerSnapshot {
        // Premier appel séquentiel : lève rapidement si l'enceinte est injoignable.
        let status = try await getData("settings:/kef/host/speakerStatus")["kefSpeakerStatus"]?.stringValue

        if cachedModel == nil {
            let release = try await getData("settings:/releasetext")["string_"]?.stringValue ?? ""
            let split = KEFParser.splitRelease(release)
            let mac = try? await getData("settings:/system/primaryMacAddress")["string_"]?.stringValue
            cachedModel = (split.model, split.firmware, mac)
        }
        async let name = getData("settings:/deviceName")
        async let source = getData("settings:/kef/play/physicalSource")
        async let volume = getData("player:volume")
        async let mute = getData("settings:/mediaPlayer/mute")
        async let player = getData("player:player/data")

        let rawModel = cachedModel?.model
        let key = KEFParser.normalizeModel(rawModel)
        let sourceRaw = try await source["kefPhysicalSource"]?.stringValue
        let playerData = try await player
        let position = try? await getData("player:player/data/playTime")["i64_"]?.intValue

        return SpeakerSnapshot(
            name: try await name["string_"]?.stringValue,
            model: key,
            modelLabel: KEFParser.modelLabels[key] ?? rawModel,
            firmware: cachedModel?.firmware,
            mac: cachedModel?.mac,
            power: status == "powerOn" ? .on : .standby,
            source: sourceRaw == "standby" ? nil : SpeakerSource.parse(sourceRaw),
            sources: KEFParser.sources(forModel: key),
            volume: try await volume["i32_"]?.intValue ?? 0,
            speakerMuted: (try? await mute["bool_"]?.boolValue) ?? false,
            player: KEFParser.playerInfo(playerData),
            positionMs: position
        )
    }

    public func playerInfo() async throws -> PlayerInfo {
        KEFParser.playerInfo(try await getData("player:player/data"))
    }

    // MARK: - Événements (long polling)

    private func subscribe() async throws -> String {
        let subscribe: [JSONValue] = KEFParser.subscribedPaths.map { ["path": .string($0), "type": "itemWithValue"] }
        let reply = try await postJSON("/api/event/modifyQueue", ["subscribe": .array(subscribe), "unsubscribe": []])
        // Réponse : une chaîne JSON "{uuid}" (accolades comprises, renvoyées telles quelles à pollQueue).
        guard let id = reply?.nonEmptyString else { throw KEFError.invalidResponse("modifyQueue") }
        queueID = id
        lastPolled = Date()
        return id
    }

    public func pollEvents(timeout: Int) async throws -> SpeakerEvents {
        let id: String
        if let queueID, let lastPolled, Date().timeIntervalSince(lastPolled) < Self.queueMaxIdle {
            id = queueID
        } else {
            id = try await subscribe()
        }
        let raw: JSONValue
        do {
            raw = try await getJSON("/api/event/pollQueue",
                                    [("queueId", id), ("timeout", String(timeout))],
                                    timeout: TimeInterval(timeout) + 3)
        } catch KEFError.http(let code, _) where code == 400 || code == 404 {
            // « Unknown queue id! » : la file a expiré (redémarrage, inactivité…).
            queueID = nil
            return SpeakerEvents()
        }
        lastPolled = Date()
        var events = KEFParser.events(raw)
        // Les événements « player:player/data » ne contiennent pas toujours `mediaRoles` :
        // pour une radio airable, on relit l'état du lecteur afin d'identifier la station.
        if let p = events.player, p.isAirableRadio, p.station == nil,
           let fresh = try? await playerInfo() {
            events.player = fresh
        }
        return events
    }

    public func resetEventQueue() async {
        queueID = nil
    }

    // MARK: - Commandes

    private func setPhysicalSource(_ value: String) async throws {
        try await setData("settings:/kef/play/physicalSource", role: "value",
                          value: ["type": "kefPhysicalSource", "kefPhysicalSource": .string(value)])
    }

    public func setPower(on: Bool) async throws {
        // Comme pykefcontrol : « powerOn » / « standby » passent par physicalSource.
        try await setPhysicalSource(on ? "powerOn" : "standby")
    }

    public func setSource(_ source: SpeakerSource) async throws {
        try await setPhysicalSource(source.rawValue)
    }

    public func setVolume(_ volume: Int) async throws {
        let v = max(0, min(100, volume))
        try await setData("player:volume", role: "value", value: ["type": "i32_", "i32_": .int(Int64(v))])
    }

    public func control(_ command: PlayerControl) async throws {
        try await setData("player:player/control", role: "activate", value: ["control": .string(command.rawValue)])
    }

    // MARK: - Radios airable

    private func radiosRootPath() async throws -> String {
        if let radiosRoot { return radiosRoot }
        // airable:linkService_airable.radios redirige vers airable:https://<ID>.airable.io/airable/radios
        let root = try await getRows(Self.radiosLink, count: 20).path
        radiosRoot = root
        return root
    }

    public func radioHistory() async throws -> [Station] {
        let root = try await radiosRootPath()
        return KEFParser.stations(fromRows: try await getRows("\(root)/history").response)
    }

    public func searchStations(_ query: String) async throws -> [Station] {
        let previous = searchTail
        let task = Task { () async throws -> [Station] in
            _ = await previous?.value
            return try await self.performSearch(query)
        }
        searchTail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func performSearch(_ query: String) async throws -> [Station] {
        let root = try await radiosRootPath()
        // Le formulaire (airable:form1, form7…) change : on le redécouvre à chaque fois.
        let form = try await getRows("\(root)/search", count: 10).response
        let rows = form["rows"]?.arrayValue ?? []
        guard let field = rows.first(where: { $0["type"]?.stringValue == "value" })?["path"]?.nonEmptyString,
              let submit = rows.first(where: { $0["type"]?.stringValue == "action" })?["path"]?.nonEmptyString
        else { throw KEFError.searchFormMissing }
        try await setData(field, role: "value", value: ["type": "string_", "string_": .string(query)], roleKey: "role")
        let result = try await setData(submit, role: "activate", value: [:], roleKey: "role")
        guard let resultsPath = result?["result"]?["path"]?.nonEmptyString else { throw KEFError.noSearchResults }
        // Les résultats mélangent des filtres (/radios/filter/…) et des stations.
        return KEFParser.stations(fromRows: try await getRows(resultsPath, count: Self.searchLimit).response)
    }

    // MARK: - Explorateur (lecture seule)

    public func browseRadios(_ location: RadioBrowseLocation, from: Int, count: Int) async throws -> RadioBrowsePage {
        let path: String
        switch location {
        case .directory(let directory): path = "\(try await radiosRootPath())/\(directory.relativePath)"
        case .path(let raw): path = raw
        }
        // Chemins opaques renvoyés par l'enceinte : seuls ceux d'airable sont parcourus.
        guard path.hasPrefix("airable:") else { throw KEFError.invalidResponse("chemin airable attendu") }
        let (response, final) = try await getRows(path, from: max(0, from), count: count)
        return KEFParser.browsePage(response, path: final, offset: max(0, from))
    }

    @discardableResult
    public func playStation(path: String) async throws -> Station {
        guard path.hasPrefix("airable:"), path.contains(KEFParser.stationMarker) else { throw KEFError.notAStation }
        // On re-résout la row audio à chaque lecture : les URLs de flux changent.
        let rows = try await getRows(path, count: 5).response["rows"]?.arrayValue ?? []
        guard let audio = rows.first(where: { $0["type"]?.stringValue == "audio" }) else {
            throw KEFError.stationUnavailable
        }
        try await setData("player:player/control", role: "activate",
                          value: ["control": "play", "mediaRoles": audio], roleKey: "role")
        return KEFParser.normalizeStation(audio)
            ?? Station(id: path, title: audio["title"]?.stringValue ?? "Radio", path: path)
    }
}
