import Foundation
import Testing
@testable import KEFKit

@MainActor
@Suite("Favoris")
struct FavoritesStoreTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("kef-fav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func station(_ n: Int) -> Station {
        Station(id: "airable://airable/radio/\(n)", title: "Radio \(n)",
                path: "airable:https://x.airable.io/id/airable/radio/\(n)", icon: "http://static.airable.io/\(n).png")
    }

    @Test func newStoreSuggestsHistory() {
        let store = FavoritesStore(fileURL: dir.appendingPathComponent("favorites.json"))
        #expect(store.items.isEmpty)
        #expect(store.suggestHistory)
    }

    @Test func addRemovePersist() throws {
        let url = dir.appendingPathComponent("favorites.json")
        let store = FavoritesStore(fileURL: url)
        #expect(store.add(station(1)))
        #expect(!store.add(station(1))) // doublon
        #expect(store.add(station(2)))
        #expect(store.contains(station(2)))

        let reloaded = FavoritesStore(fileURL: url)
        #expect(reloaded.items.map(\.id) == [station(1).id, station(2).id])

        // Format identique au client web.
        let json = try JSONValue.parse(Data(contentsOf: url))
        #expect(json["version"] == 1)
        #expect(json["suggest_history"] == true)
        #expect(json["items"]?[0]?["path"]?.stringValue == station(1).path)
        #expect(json["items"]?[0]?["icon"]?.stringValue == "http://static.airable.io/1.png")

        #expect(reloaded.remove(station(1)))
        #expect(!reloaded.remove(station(1)))
        #expect(FavoritesStore(fileURL: url).items.map(\.id) == [station(2).id])
    }

    @Test func reorderAndMove() {
        let store = FavoritesStore(fileURL: dir.appendingPathComponent("favorites.json"))
        (1...4).forEach { store.add(station($0)) }
        store.move(id: station(4).id, before: station(1).id)
        #expect(store.items.map(\.title) == ["Radio 4", "Radio 1", "Radio 2", "Radio 3"])
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(store.items.map(\.title) == ["Radio 1", "Radio 2", "Radio 3", "Radio 4"])
        store.reorder(ids: [station(3).id, "inconnu", station(1).id])
        #expect(store.items.map(\.title) == ["Radio 3", "Radio 1", "Radio 2", "Radio 4"])
    }

    @Test func importWebClientFile() throws {
        // Fichier tel qu'écrit par le client web (FavoritesStore.save en Python).
        let web = """
        {
          "version": 1,
          "suggest_history": false,
          "items": [
            {"id": "airable://airable/radio/1", "title": "Radio 1", "path": "airable:https://x.airable.io/id/airable/radio/1", "icon": null, "description": "Jazz"},
            {"id": "airable://airable/radio/9", "title": "FIP", "path": "airable:https://x.airable.io/id/airable/radio/9", "icon": "http://static.airable.io/9.png", "description": null},
            {"id": "", "title": "invalide", "path": "x"},
            {"id": "airable://airable/radio/9", "title": "doublon", "path": "y"}
          ]
        }
        """
        let src = dir.appendingPathComponent("web-favorites.json")
        try Data(web.utf8).write(to: src)

        let store = FavoritesStore(fileURL: dir.appendingPathComponent("favorites.json"))
        store.add(station(1))
        let added = try store.importFile(at: src)
        #expect(added == 1) // Radio 1 existait déjà ; invalide et doublon ignorés
        #expect(store.items.map(\.title) == ["Radio 1", "FIP"])
        #expect(!store.suggestHistory)

        // Un simple tableau est aussi accepté.
        let arr = dir.appendingPathComponent("array.json")
        try Data(#"[{"id":"a","title":"A","path":"p"}]"#.utf8).write(to: arr)
        #expect(try store.importFile(at: arr) == 1)

        let bad = dir.appendingPathComponent("bad.json")
        try Data("pas du json".utf8).write(to: bad)
        #expect(throws: (any Error).self) { try store.importFile(at: bad) }
    }

    @Test func dismissSuggestionsPersists() {
        let url = dir.appendingPathComponent("favorites.json")
        FavoritesStore(fileURL: url).dismissSuggestions()
        #expect(!FavoritesStore(fileURL: url).suggestHistory)
    }

    @Test func corruptFileIsIgnored() throws {
        let url = dir.appendingPathComponent("favorites.json")
        try Data("{oops".utf8).write(to: url)
        let store = FavoritesStore(fileURL: url)
        #expect(store.items.isEmpty)
        #expect(store.lastError != nil)
    }
}
