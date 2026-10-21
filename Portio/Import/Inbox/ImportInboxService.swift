import Foundation
import Observation

/// Liest den Share-Extension-Eingang aus dem App-Group-Container aus.
@MainActor
@Observable
final class ImportInboxService {
    struct DrainedItem: Identifiable {
        let item: ImportInboxItem
        let imageData: Data?
        var id: UUID { item.id }
    }

    private(set) var lastDrainCount = 0

    /// Holt alle wartenden Items ab (älteste zuerst) und räumt den Ordner auf.
    func drain() async -> [DrainedItem] {
        guard let directory = ImportInbox.directory else { return [] }
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var drained: [DrainedItem] = []
        for jsonURL in urls where jsonURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: jsonURL),
                  let item = try? decoder.decode(ImportInboxItem.self, from: data) else {
                try? fileManager.removeItem(at: jsonURL)
                continue
            }
            var imageData: Data?
            if let fileName = item.imageFileName {
                let imageURL = directory.appendingPathComponent(fileName)
                imageData = try? Data(contentsOf: imageURL)
                try? fileManager.removeItem(at: imageURL)
            }
            try? fileManager.removeItem(at: jsonURL)
            drained.append(DrainedItem(item: item, imageData: imageData))
        }
        drained.sort { $0.item.createdAt < $1.item.createdAt }
        lastDrainCount = drained.count
        return drained
    }
}
