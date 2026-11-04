import Foundation
import Observation
import os

/// Radios favorites, stockées localement (jamais sur l'enceinte) dans un fichier JSON
/// au même format que le client web :
///
/// ```json
/// {"version": 1, "suggest_history": true, "items": [{"id", "title", "path", "icon", "description"}]}
/// ```
@MainActor
@Observable
public final class FavoritesStore {
    public private(set) var items: [Station] = []
    /// Vrai tant que l'utilisateur n'a pas écarté les suggestions issues de l'historique radio.
    public private(set) var suggestHistory = true
    public let fileURL: URL
    public private(set) var lastError: String?

    private static let log = Logger(subsystem: "fr.wedooit.kefremote", category: "favorites")

    /// `~/Library/Application Support/KEF Remote/<name>`
    public static func defaultURL(fileName: String = "favorites.json") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("KEF Remote", isDirectory: true).appendingPathComponent(fileName)
    }

    public init(fileURL: URL = FavoritesStore.defaultURL()) {
        self.fileURL = fileURL
        load()
    }

    // MARK: Fichier

    struct FileFormat: Codable {
        var version: Int = 1
        var suggest_history: Bool?
        var items: [RawStation]
    }

    /// Station telle que lue sur disque : champs optionnels, nettoyés ensuite.
    struct RawStation: Codable {
        var id: String?
        var title: String?
        var path: String?
        var icon: String?
        var description: String?

        var cleaned: Station? {
            guard let id, !id.isEmpty, let title, !title.isEmpty, let path, !path.isEmpty else { return nil }
            return Station(id: id, title: title, path: path, icon: icon, description: description)
        }
    }

    /// Lit un fichier de favoris : objet `{items: […]}` (format du client web) ou simple tableau.
    public static func decode(_ data: Data) throws -> (items: [Station], suggestHistory: Bool?) {
        let decoder = JSONDecoder()
        let raws: [RawStation]
        var suggest: Bool?
        if let file = try? decoder.decode(FileFormat.self, from: data) {
            raws = file.items
            suggest = file.suggest_history
        } else {
            raws = try decoder.decode([RawStation].self, from: data)
        }
        var seen = Set<String>()
        let items = raws.compactMap(\.cleaned).filter { seen.insert($0.id).inserted }
        return (items, suggest)
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try Self.decode(data)
            items = decoded.items
            // Comme le client web : un fichier existant sans le champ désactive les suggestions.
            suggestHistory = decoded.suggestHistory ?? false
        } catch {
            Self.log.warning("favorites.json illisible : \(error.localizedDescription, privacy: .public)")
            lastError = "Fichier de favoris illisible"
        }
    }

    public func save() {
        let file = FileFormat(suggest_history: suggestHistory, items: items.map {
            RawStation(id: $0.id, title: $0.title, path: $0.path, icon: $0.icon, description: $0.description)
        })
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            var data = try encoder.encode(file)
            data.append(0x0A)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Écriture atomique : un crash ne laisse jamais un fichier tronqué.
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            Self.log.error("Écriture des favoris impossible : \(error.localizedDescription, privacy: .public)")
            lastError = "Impossible d'enregistrer les favoris"
        }
    }

    // MARK: Opérations

    public func contains(_ station: Station?) -> Bool {
        guard let station else { return false }
        return items.contains { $0.isSameStation(as: station) }
    }

    /// Ajoute en fin de liste ; `false` si déjà présente.
    @discardableResult
    public func add(_ station: Station) -> Bool {
        guard !contains(station) else { return false }
        items.append(station)
        save()
        return true
    }

    @discardableResult
    public func remove(_ station: Station) -> Bool {
        let before = items.count
        items.removeAll { $0.isSameStation(as: station) }
        guard items.count != before else { return false }
        save()
        return true
    }

    public func toggle(_ station: Station) {
        if contains(station) { remove(station) } else { add(station) }
    }

    /// Déplace la station `id` à la position occupée par `targetID` (glisser-déposer).
    public func move(id: String, before targetID: String) {
        guard id != targetID, let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        let station = items.remove(at: from)
        items.insert(station, at: to)
        save()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { items[$0] }
        var rest = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        items = rest
        save()
    }

    /// Réordonne selon `ids` ; les inconnus sont ignorés, les oubliés gardés à la fin.
    public func reorder(ids: [String]) {
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ordered: [Station] = []
        for id in ids { if let s = byID.removeValue(forKey: id) { ordered.append(s) } }
        items = ordered + items.filter { byID[$0.id] != nil }
        save()
    }

    public func dismissSuggestions() {
        suggestHistory = false
        save()
    }

    /// Importe un fichier de favoris (ex. celui du client web) ; renvoie le nombre de stations ajoutées.
    @discardableResult
    public func importFile(at url: URL) throws -> Int {
        let decoded = try Self.decode(try Data(contentsOf: url))
        var added = 0
        for station in decoded.items where !contains(station) {
            items.append(station)
            added += 1
        }
        if added > 0 || !items.isEmpty { suggestHistory = false }
        save()
        return added
    }
}
