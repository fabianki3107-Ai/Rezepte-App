import Foundation
import SwiftData

/// Ein lokal gespeichertes Rezept.
///
/// Hinweise zum Schema:
/// - Enums werden als `String`-Rohwerte gespeichert, damit sie in `#Predicate` nutzbar bleiben.
/// - Relationen sind in SwiftData ungeordnet; die Reihenfolge wird über `sortIndex` gehalten
///   und über `sortedIngredients` / `sortedSteps` bereitgestellt.
/// - Bilder liegen per `.externalStorage` außerhalb der SQLite-Datei, Thumbnails klein im Store.
@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String?
    var servings: Int
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var difficultyRaw: String
    var createdAt: Date
    var updatedAt: Date
    var lastCookedAt: Date?
    var isFavorite: Bool
    var notes: String?

    // Herkunft & Vertrauen
    var sourceKindRaw: String
    var sourceURL: URL?
    var sourceAuthor: String?
    /// Durchschnittliche Vision-OCR-Konfidenz (0...1), nil bei manueller Eingabe.
    var ocrConfidence: Double?
    var verificationRaw: String

    @Attribute(.externalStorage) var heroImageData: Data?
    var thumbnailData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient] = []

    @Relationship(deleteRule: .cascade, inverse: \CookingStep.recipe)
    var steps: [CookingStep] = []

    @Relationship(inverse: \Tag.recipes)
    var tags: [Tag] = []

    init(
        id: UUID = UUID(),
        title: String,
        summary: String? = nil,
        servings: Int = 4,
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        difficulty: Difficulty = .medium,
        source: ImportSource = .manual,
        sourceAuthor: String? = nil,
        ocrConfidence: Double? = nil,
        verification: VerificationState = .unverified,
        heroImageData: Data? = nil,
        thumbnailData: Data? = nil,
        isFavorite: Bool = false,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = max(1, servings)
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.difficultyRaw = difficulty.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isFavorite = isFavorite
        self.notes = notes
        self.sourceKindRaw = source.kind.rawValue
        self.sourceURL = source.url
        self.sourceAuthor = sourceAuthor
        self.ocrConfidence = ocrConfidence
        self.verificationRaw = verification.rawValue
        self.heroImageData = heroImageData
        self.thumbnailData = thumbnailData
    }

    // MARK: Typed Accessors

    var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRaw) ?? .medium }
        set { difficultyRaw = newValue.rawValue }
    }

    var source: ImportSource {
        get { ImportSource(kind: ImportSource.Kind(rawValue: sourceKindRaw) ?? .manual, url: sourceURL) }
        set { sourceKindRaw = newValue.kind.rawValue; sourceURL = newValue.url }
    }

    var verification: VerificationState {
        get { VerificationState(rawValue: verificationRaw) ?? .unverified }
        set { verificationRaw = newValue.rawValue }
    }

    var sortedIngredients: [Ingredient] { ingredients.sorted { $0.sortIndex < $1.sortIndex } }
    var sortedSteps: [CookingStep] { steps.sorted { $0.sortIndex < $1.sortIndex } }

    var totalTimeMinutes: Int? {
        switch (prepTimeMinutes, cookTimeMinutes) {
        case (nil, nil): return nil
        case let (p?, nil): return p
        case let (nil, c?): return c
        case let (p?, c?): return p + c
        }
    }

    /// Zutaten gruppiert nach optionaler Gruppenüberschrift ("Für den Teig"), Reihenfolge stabil.
    var ingredientGroups: [(title: String?, items: [Ingredient])] {
        var order: [String?] = []
        var buckets: [String?: [Ingredient]] = [:]
        for ingredient in sortedIngredients {
            let key = ingredient.group
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(ingredient)
        }
        return order.map { (title: $0, items: buckets[$0] ?? []) }
    }

    /// Markiert eine Änderung; wird vom Repository vor dem Speichern aufgerufen.
    func touch(now: Date = .now) {
        updatedAt = now
    }
}

// MARK: - Hilfstypen

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Einfach"
        case .medium: return "Mittel"
        case .hard: return "Anspruchsvoll"
        }
    }

    var symbolName: String {
        switch self {
        case .easy: return "1.circle"
        case .medium: return "2.circle"
        case .hard: return "3.circle"
        }
    }
}

/// Woher ein Rezept stammt. Rein informativ – es findet kein Sync statt.
struct ImportSource: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case manual
        case instagram
        case screenshot
        case photo
        case shared

        var title: String {
            switch self {
            case .manual: return "Manuell"
            case .instagram: return "Instagram"
            case .screenshot: return "Screenshot"
            case .photo: return "Foto"
            case .shared: return "Geteilt"
            }
        }

        var symbolName: String {
            switch self {
            case .manual: return "pencil"
            case .instagram: return "camera.aperture"
            case .screenshot: return "rectangle.on.rectangle"
            case .photo: return "camera"
            case .shared: return "square.and.arrow.down"
            }
        }
    }

    var kind: Kind
    var url: URL?

    static let manual = ImportSource(kind: .manual, url: nil)
    static func instagram(_ url: URL) -> ImportSource { ImportSource(kind: .instagram, url: url) }
    static let screenshot = ImportSource(kind: .screenshot, url: nil)
    static let photo = ImportSource(kind: .photo, url: nil)
}

/// Prüfstatus für das Vertrauens-Badge (Mint = verifiziert).
enum VerificationState: String, Codable {
    /// Automatisch importiert, noch nicht vom Nutzer durchgesehen.
    case unverified
    /// Nutzer hat Zutaten und Schritte kontrolliert.
    case userVerified
    /// Nutzer hat das Rezept mindestens einmal gekocht.
    case cooked
}
