import Foundation

/// Nährwerte als Werttyp: Kalorien (kcal) und Makros in Gramm.
struct NutritionFacts: Hashable, Codable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = NutritionFacts(calories: 0, protein: 0, carbs: 0, fat: 0)

    /// Kalorien aus Makros (4/4/9) – Plausibilitätsprüfung und Fallback.
    var caloriesFromMacros: Double { protein * 4 + carbs * 4 + fat * 9 }

    var isEmpty: Bool { calories <= 0 && protein <= 0 && carbs <= 0 && fat <= 0 }

    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    /// Kalorien ganzzahlig, Makros auf eine Nachkommastelle.
    func rounded() -> NutritionFacts {
        NutritionFacts(
            calories: calories.rounded(),
            protein: (protein * 10).rounded() / 10,
            carbs: (carbs * 10).rounded() / 10,
            fat: (fat * 10).rounded() / 10
        )
    }

    func value(for macro: Macro) -> Double {
        switch macro {
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        }
    }

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                       carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }

    static func += (lhs: inout NutritionFacts, rhs: NutritionFacts) { lhs = lhs + rhs }
}

/// Die drei Makronährstoffe mit Anzeige-Metadaten.
enum Macro: String, CaseIterable, Identifiable, Codable {
    case protein, carbs, fat
    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: return "Eiweiß"
        case .carbs: return "Kohlenhydrate"
        case .fat: return "Fett"
        }
    }

    var shortTitle: String {
        switch self {
        case .protein: return "Eiweiß"
        case .carbs: return "Carbs"
        case .fat: return "Fett"
        }
    }

    var symbolName: String {
        switch self {
        case .protein: return "bolt.fill"
        case .carbs: return "leaf.fill"
        case .fat: return "drop.fill"
        }
    }

    /// kcal pro Gramm.
    var caloriesPerGram: Double { self == .fat ? 9 : 4 }
}

/// Herkunft der Nährwerte eines Rezepts.
enum NutritionSource: String, Codable {
    /// Noch nicht berechnet.
    case none
    /// Lokal aus den Zutaten geschätzt (`LocalNutritionParser`).
    case estimated
    /// Im Rezepttext deklariert ("450 kcal, 30 g Eiweiß …").
    case declared
    /// Vom Nutzer eingetragen.
    case manual

    var title: String {
        switch self {
        case .none: return "Nicht berechnet"
        case .estimated: return "Geschätzt aus Zutaten"
        case .declared: return "Aus dem Rezept übernommen"
        case .manual: return "Manuell eingetragen"
        }
    }
}

/// Tagesziele des Nutzers.
struct NutritionGoals: Hashable, Codable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    static let `default` = NutritionGoals(calories: 2000, protein: 120, carbs: 230, fat: 70)

    func goal(for macro: Macro) -> Int {
        switch macro {
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        }
    }

    /// Kalorien, die sich aus den Makro-Zielen ergeben – zur Plausibilitätsanzeige in den Einstellungen.
    var caloriesFromMacroGoals: Int { protein * 4 + carbs * 4 + fat * 9 }
}
