import Foundation

/// Austauschformat zwischen Share-Extension und App über den App-Group-Container.
///
/// Die Extension schreibt eine JSON-Datei (+ optional ein Bild) in `ImportInbox.directory`,
/// die App liest den Eingang beim nächsten Aktivwerden aus und löscht ihn.
/// Beide Targets kompilieren diese Datei, deshalb keine UIKit-/SwiftData-Abhängigkeiten.
struct ImportInboxItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case url, text, image
    }

    var id: UUID
    var createdAt: Date
    var kind: Kind
    var url: URL?
    var text: String?
    /// Dateiname des Bildes im Inbox-Ordner (JPEG/PNG), relativ.
    var imageFileName: String?

    init(id: UUID = UUID(), createdAt: Date = .now, kind: Kind, url: URL? = nil, text: String? = nil, imageFileName: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.url = url
        self.text = text
        self.imageFileName = imageFileName
    }
}

enum ImportInbox {
    /// Muss mit den Entitlements beider Targets übereinstimmen.
    static let appGroupIdentifier = "group.de.fabian.rezepte"
    static let directoryName = "ImportInbox"

    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Schreibt ein Item (und optional Bilddaten) atomar in den Eingang.
    @discardableResult
    static func enqueue(_ item: ImportInboxItem, imageData: Data? = nil) throws -> ImportInboxItem {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var stored = item
        if let imageData {
            let fileName = "\(item.id.uuidString).img"
            try imageData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            stored.imageFileName = fileName
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(stored)
        try data.write(to: directory.appendingPathComponent("\(item.id.uuidString).json"), options: .atomic)
        return stored
    }
}
