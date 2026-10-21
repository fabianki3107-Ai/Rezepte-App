import Foundation
import SwiftData

/// Frei vergebbare Schlagwörter ("Vegan", "Schnell", "Dessert").
@Model
final class Tag {
    @Attribute(.unique) var name: String
    var recipes: [RecipeItem] = []

    init(name: String) {
        self.name = Tag.normalized(name)
    }

    /// Einheitliche Schreibweise, damit "vegan" und "Vegan" nicht doppelt existieren.
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}
