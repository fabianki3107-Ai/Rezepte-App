import Foundation
import SwiftData

/// Einzige Schreibstelle für Rezepte. Views lesen über `@Query`, schreiben über das Repository,
/// damit `updatedAt`, Tag-Deduplizierung und Fehlerbehandlung an einem Ort liegen.
@MainActor
final class RecipeRepository {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    var context: ModelContext { modelContainer.mainContext }

    // MARK: - Anlegen aus Entwurf

    @discardableResult
    func save(draft: ParsedRecipeDraft) throws -> RecipeItem {
        let recipe = RecipeItem(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: draft.summary?.nilIfBlank,
            servings: draft.servings ?? 4,
            prepTimeMinutes: draft.prepTimeMinutes,
            cookTimeMinutes: draft.cookTimeMinutes,
            source: draft.source,
            sourceAuthor: draft.sourceAuthor?.nilIfBlank,
            ocrConfidence: draft.ocrConfidence,
            verification: .unverified,
            heroImageData: draft.heroImageData,
            thumbnailData: draft.heroImageData.flatMap { ImageProcessing.thumbnailData(from: $0) },
            notes: draft.notes?.nilIfBlank
        )
        context.insert(recipe)

        recipe.ingredients = draft.ingredients.enumerated().map { index, item in
            Ingredient(
                sortIndex: index,
                name: item.name,
                quantity: item.quantity,
                quantityUpperBound: item.quantityUpperBound,
                unit: item.unit,
                note: item.note?.nilIfBlank,
                group: item.group?.nilIfBlank,
                isScalable: item.isScalable,
                isOptional: item.isOptional
            )
        }
        recipe.steps = draft.steps.enumerated().map { index, step in
            CookingStep(
                sortIndex: index,
                text: step.text,
                durationSeconds: step.durationSeconds,
                temperatureCelsius: step.temperatureCelsius
            )
        }
        recipe.tags = try draft.tags.map { try tag(named: $0) }

        // Lokale Nährwert-Schätzung direkt beim Import – deklarierte Werte im Text haben Vorrang.
        let estimate = LocalNutritionParser.estimate(draft: draft)
        if estimate.isUsable {
            recipe.applyNutrition(estimate.perServing, confidence: estimate.confidence, source: estimate.source)
        }

        try context.save()
        return recipe
    }

    /// Schätzung erneut ausführen, z. B. nach geänderten Zutaten. Manuelle Werte werden nur auf Wunsch überschrieben.
    @discardableResult
    func recalculateNutrition(_ recipe: RecipeItem, overrideManual: Bool = false) throws -> NutritionEstimate {
        let estimate = LocalNutritionParser.estimate(recipe: recipe)
        if recipe.nutritionSource != .manual || overrideManual {
            recipe.applyNutrition(estimate.perServing, confidence: estimate.confidence, source: estimate.source)
            try update(recipe)
        }
        return estimate
    }

    func setManualNutrition(_ recipe: RecipeItem, facts: NutritionFacts) throws {
        recipe.applyNutrition(facts, confidence: 1, source: .manual)
        try update(recipe)
    }

    // MARK: - Mutationen

    func update(_ recipe: RecipeItem) throws {
        recipe.touch()
        try context.save()
    }

    func toggleFavorite(_ recipe: RecipeItem) throws {
        recipe.isFavorite.toggle()
        try update(recipe)
    }

    func markVerified(_ recipe: RecipeItem) throws {
        if recipe.verification == .unverified {
            recipe.verification = .userVerified
        }
        try update(recipe)
    }

    func markCooked(_ recipe: RecipeItem, at date: Date = .now) throws {
        recipe.lastCookedAt = date
        recipe.verification = .cooked
        try update(recipe)
    }

    func replaceHeroImage(_ recipe: RecipeItem, with data: Data?) throws {
        recipe.heroImageData = data
        recipe.thumbnailData = data.flatMap { ImageProcessing.thumbnailData(from: $0) }
        try update(recipe)
    }

    func delete(_ recipe: RecipeItem) throws {
        context.delete(recipe)
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: RecipeItem.self)
        try context.delete(model: Tag.self)
        try context.save()
    }

    // MARK: - Tags

    func tag(named rawName: String) throws -> Tag {
        let name = Tag.normalized(rawName)
        var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: name)
        context.insert(tag)
        return tag
    }

    // MARK: - Export (lokal, als Datei teilbar)

    /// JSON-Export aller Rezepte, z. B. für Backups über die Dateien-App. Kein Upload.
    func exportJSON() throws -> Data {
        let recipes = try context.fetch(FetchDescriptor<RecipeItem>(sortBy: [SortDescriptor(\.title)]))
        let payload = RecipeExport(exportedAt: .now, recipes: recipes.map(RecipeExport.Entry.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}

/// Serialisierbares Export-Schema (bewusst von den SwiftData-Klassen entkoppelt).
struct RecipeExport: Codable {
    var version = 1
    var exportedAt: Date
    var recipes: [Entry]

    struct Entry: Codable {
        var title: String
        var summary: String?
        var notes: String?
        var servings: Int
        var prepTimeMinutes: Int?
        var cookTimeMinutes: Int?
        var difficulty: String
        var sourceKind: String
        var sourceURL: URL?
        var sourceAuthor: String?
        var tags: [String]
        var caloriesPerServing: Int
        var proteinGrams: Double
        var carbsGrams: Double
        var fatGrams: Double
        var nutritionSource: String
        var ingredients: [IngredientEntry]
        var steps: [StepEntry]

        struct IngredientEntry: Codable {
            var name: String
            var quantity: Double?
            var quantityUpperBound: Double?
            var unit: String
            var note: String?
            var group: String?
            var isScalable: Bool
            var isOptional: Bool
        }

        struct StepEntry: Codable {
            var text: String
            var durationSeconds: Int?
            var temperatureCelsius: Int?
        }

        @MainActor
        init(_ recipe: RecipeItem) {
            title = recipe.title
            summary = recipe.summary
            notes = recipe.notes
            servings = recipe.servings
            prepTimeMinutes = recipe.prepTimeMinutes
            cookTimeMinutes = recipe.cookTimeMinutes
            difficulty = recipe.difficultyRaw
            sourceKind = recipe.sourceKindRaw
            sourceURL = recipe.sourceURL
            sourceAuthor = recipe.sourceAuthor
            tags = recipe.tags.map(\.name).sorted()
            caloriesPerServing = recipe.caloriesPerServing
            proteinGrams = recipe.proteinGrams
            carbsGrams = recipe.carbsGrams
            fatGrams = recipe.fatGrams
            nutritionSource = recipe.nutritionSourceRaw
            ingredients = recipe.sortedIngredients.map {
                IngredientEntry(name: $0.name, quantity: $0.quantity, quantityUpperBound: $0.quantityUpperBound,
                                unit: $0.unitRaw, note: $0.note, group: $0.group,
                                isScalable: $0.isScalable, isOptional: $0.isOptional)
            }
            steps = recipe.sortedSteps.map {
                StepEntry(text: $0.text, durationSeconds: $0.durationSeconds, temperatureCelsius: $0.temperatureCelsius)
            }
        }
    }
}

extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
