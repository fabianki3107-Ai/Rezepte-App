import Foundation
import SwiftData

/// Ein Kalendertag im Kalorien-Tagebuch mit denormalisierten Tagessummen.
///
/// Die Summen werden bei jeder Änderung über `recalculateTotals()` neu berechnet und gespeichert,
/// damit Dashboard und Wochen-Chart ohne Aggregation über Einträge auskommen.
@Model
final class DailyLog {
    @Attribute(.unique) var id: UUID
    /// Tagesbeginn in der lokalen Zeitzone; eindeutig pro Tag.
    @Attribute(.unique) var dayStart: Date
    var totalCalories: Int
    var totalProtein: Double
    var totalCarbs: Double
    var totalFat: Double

    @Relationship(deleteRule: .cascade, inverse: \LogEntry.log)
    var entries: [LogEntry] = []

    init(id: UUID = UUID(), day: Date, calendar: Calendar = .current) {
        self.id = id
        self.dayStart = calendar.startOfDay(for: day)
        self.totalCalories = 0
        self.totalProtein = 0
        self.totalCarbs = 0
        self.totalFat = 0
    }

    var sortedEntries: [LogEntry] { entries.sorted { $0.loggedAt < $1.loggedAt } }

    /// Heute gegessene Rezepte in Reihenfolge des Loggens (Rezepte können mehrfach vorkommen).
    var consumedRecipes: [RecipeItem] { sortedEntries.compactMap(\.recipe) }

    var totals: NutritionFacts {
        NutritionFacts(calories: Double(totalCalories), protein: totalProtein, carbs: totalCarbs, fat: totalFat)
    }

    func recalculateTotals() {
        let sum = entries.reduce(NutritionFacts.zero) { $0 + $1.facts }
        totalCalories = Int(sum.calories.rounded())
        totalProtein = (sum.protein * 10).rounded() / 10
        totalCarbs = (sum.carbs * 10).rounded() / 10
        totalFat = (sum.fat * 10).rounded() / 10
    }

    func isSameDay(as date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(dayStart, inSameDayAs: date)
    }
}

/// Ein geloggtes Rezept mit Portionszahl und Nährwert-Snapshot zum Zeitpunkt des Loggens.
/// Der Snapshot schützt das Tagebuch vor späteren Änderungen am Rezept.
@Model
final class LogEntry {
    @Attribute(.unique) var id: UUID
    var loggedAt: Date
    var servings: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var mealRaw: String
    /// Titel-Kopie, damit der Eintrag auch nach Löschen des Rezepts lesbar bleibt.
    var recipeTitle: String
    var healthKitStateRaw: String
    /// Version für `HKMetadataKeySyncVersion`; jede Änderung erhöht sie, HealthKit ersetzt ältere Samples.
    var healthKitSyncVersion: Int

    var recipe: RecipeItem?
    var log: DailyLog?

    init(
        id: UUID = UUID(),
        loggedAt: Date = .now,
        servings: Double,
        facts: NutritionFacts,
        meal: MealSlot,
        recipe: RecipeItem?,
        recipeTitle: String
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.servings = servings
        self.calories = Int(facts.calories.rounded())
        self.protein = facts.protein
        self.carbs = facts.carbs
        self.fat = facts.fat
        self.mealRaw = meal.rawValue
        self.recipeTitle = recipeTitle
        self.healthKitStateRaw = HealthKitSyncState.notSynced.rawValue
        self.healthKitSyncVersion = 0
        self.recipe = recipe
    }

    var facts: NutritionFacts {
        get { NutritionFacts(calories: Double(calories), protein: protein, carbs: carbs, fat: fat) }
        set {
            calories = Int(newValue.calories.rounded())
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }

    var meal: MealSlot {
        get { MealSlot(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var healthKitState: HealthKitSyncState {
        get { HealthKitSyncState(rawValue: healthKitStateRaw) ?? .notSynced }
        set { healthKitStateRaw = newValue.rawValue }
    }

    /// Eindeutiger Schlüssel für `HKMetadataKeySyncIdentifier`.
    var healthKitSyncIdentifier: String { "de.fabian.rezepte.app.log.\(id.uuidString)" }

    var displayTitle: String { recipe?.title ?? recipeTitle }
}

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "Frühstück"
        case .lunch: return "Mittagessen"
        case .dinner: return "Abendessen"
        case .snack: return "Snack"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "takeoutbag.and.cup.and.straw.fill"
        }
    }

    /// Plausible Mahlzeit anhand der Uhrzeit – vom Nutzer jederzeit änderbar.
    static func guess(for date: Date, calendar: Calendar = .current) -> MealSlot {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

enum HealthKitSyncState: String, Codable {
    case notSynced, synced, failed, disabled

    var title: String {
        switch self {
        case .notSynced: return "Noch nicht in Health"
        case .synced: return "In Apple Health"
        case .failed: return "Health-Sync fehlgeschlagen"
        case .disabled: return "Health-Sync aus"
        }
    }
}
