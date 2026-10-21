import Foundation

/// Eingabe für die Schätzung – entkoppelt von SwiftData, damit Entwürfe und Rezepte gleich behandelt werden.
struct IngredientInput: Hashable {
    var name: String
    var measure: Measure

    init(name: String, measure: Measure) {
        self.name = name
        self.measure = measure
    }

    init(_ ingredient: Ingredient) {
        self.init(name: ingredient.name, measure: ingredient.measure)
    }

    init(_ draft: DraftIngredient) {
        self.init(name: draft.name, measure: draft.measure)
    }
}

/// Ergebnis der lokalen Nährwert-Schätzung mit Nachvollziehbarkeit pro Zutat.
struct NutritionEstimate: Hashable {
    struct Item: Hashable, Identifiable {
        var id = UUID()
        var name: String
        var grams: Double
        var facts: NutritionFacts
        var matchedFood: String?
        var assumptions: [Assumption]
        var isMatched: Bool { matchedFood != nil }
    }

    enum Assumption: String, Hashable {
        /// Lebensmittel nicht in der Datenbank – trägt 0 kcal bei.
        case unknownFood
        /// Keine Mengenangabe ("Öl zum Braten") – trägt 0 g bei.
        case quantityMissing
        /// Stückgewicht aus Standardwert statt Lebensmittel-spezifisch.
        case defaultPieceWeight
        /// Volumen über Dichte 1,0 umgerechnet.
        case defaultDensity
        /// Packungs-/Dosengröße aus Standardwert.
        case defaultPackageSize

        var message: String {
            switch self {
            case .unknownFood: return "nicht in der Datenbank"
            case .quantityMissing: return "ohne Mengenangabe"
            case .defaultPieceWeight: return "Standard-Stückgewicht"
            case .defaultDensity: return "Standard-Dichte"
            case .defaultPackageSize: return "Standard-Packungsgröße"
            }
        }
    }

    var servings: Int
    var total: NutritionFacts
    var perServing: NutritionFacts
    /// 0...1 – Anteil der zugeordneten Masse, abgewertet um Annahmen.
    var confidence: Double
    var source: NutritionSource
    var items: [Item]

    var unmatchedNames: [String] { items.filter { !$0.isMatched && !$0.assumptions.contains(.quantityMissing) }.map(\.name) }
    var isUsable: Bool { perServing.calories > 0 }

    /// Ab diesem Wert gilt die Schätzung als verlässlich (Mint-Badge).
    static let goodConfidenceThreshold = 0.7
}

/// Heuristischer, komplett lokaler Nährwert-Schätzer.
///
/// 1. Explizit deklarierte Nährwerte im Rezepttext haben Vorrang ("450 kcal · 30 g Eiweiß …").
/// 2. Sonst wird jede Zutat über `FoodDatabase` zugeordnet, ihre Menge in Gramm umgerechnet
///    (`GramsEstimator`) und die Nährwerte pro 100 g skaliert.
/// 3. Summe geteilt durch Portionen; Konfidenz aus Massen-Abdeckung und Annahmen.
enum LocalNutritionParser {
    static func estimate(ingredients: [IngredientInput], servings: Int, rawText: String? = nil) -> NutritionEstimate {
        let portions = max(1, servings)

        if let rawText, let declared = NutritionTextExtractor.extract(from: rawText) {
            return NutritionEstimate(
                servings: portions,
                total: declared.scaled(by: Double(portions)).rounded(),
                perServing: declared.rounded(),
                confidence: 0.95,
                source: .declared,
                items: []
            )
        }

        var items: [NutritionEstimate.Item] = []
        var total = NutritionFacts.zero
        var matchedGrams = 0.0
        var totalGrams = 0.0
        var penalty = 0.0

        for input in ingredients {
            let food = FoodDatabase.match(input.name)
            var assumptions: [NutritionEstimate.Assumption] = []
            let grams = GramsEstimator.grams(for: input.measure, food: food, assumptions: &assumptions)

            var facts = NutritionFacts.zero
            if let food {
                facts = food.per100g.scaled(by: grams / 100)
                matchedGrams += grams
            } else {
                assumptions.append(.unknownFood)
            }
            totalGrams += grams

            // Annahmen gewichten: unbekannte Lebensmittel und fehlende Mengen bei kalorienreichen Zutaten zählen stärker
            if food == nil, grams > 0 { penalty += 0.12 }
            if assumptions.contains(.quantityMissing), food?.isCaloric ?? true, food != nil { penalty += 0.08 }
            if assumptions.contains(.defaultPieceWeight) { penalty += 0.08 }
            if assumptions.contains(.defaultPackageSize) || assumptions.contains(.defaultDensity) { penalty += 0.03 }

            total += facts
            items.append(NutritionEstimate.Item(name: input.name, grams: grams, facts: facts, matchedFood: food?.name, assumptions: assumptions))
        }

        let coverage = totalGrams > 0 ? matchedGrams / totalGrams : 0
        let confidence = max(0, min(1, coverage * (1 - min(0.5, penalty))))
        let perServing = total.scaled(by: 1 / Double(portions))

        return NutritionEstimate(
            servings: portions,
            total: total.rounded(),
            perServing: perServing.rounded(),
            confidence: items.isEmpty ? 0 : confidence,
            source: .estimated,
            items: items
        )
    }

    @MainActor
    static func estimate(recipe: RecipeItem, rawText: String? = nil) -> NutritionEstimate {
        estimate(ingredients: recipe.sortedIngredients.map(IngredientInput.init), servings: recipe.servings, rawText: rawText)
    }

    static func estimate(draft: ParsedRecipeDraft) -> NutritionEstimate {
        estimate(ingredients: draft.ingredients.map(IngredientInput.init), servings: draft.servings ?? 4, rawText: draft.rawText)
    }
}

/// Rechnet Mengenangaben in Gramm um – mit lebensmittelspezifischen Werten, sonst Küchen-Standards.
enum GramsEstimator {
    static func grams(for measure: Measure, food: FoodEntry?, assumptions: inout [NutritionEstimate.Assumption]) -> Double {
        guard let quantity = effectiveQuantity(measure) else {
            assumptions.append(.quantityMissing)
            return 0
        }
        let density = food?.density ?? 1.0

        switch measure.unit {
        case .gram: return quantity
        case .kilogram: return quantity * 1000
        case .pound: return quantity * 453.6
        case .ounce: return quantity * 28.35

        case .milliliter: return volume(quantity, density: density, food: food, assumptions: &assumptions)
        case .centiliter: return volume(quantity * 10, density: density, food: food, assumptions: &assumptions)
        case .deciliter: return volume(quantity * 100, density: density, food: food, assumptions: &assumptions)
        case .liter: return volume(quantity * 1000, density: density, food: food, assumptions: &assumptions)

        case .teaspoon:
            if let specific = food?.tspGrams { return quantity * specific }
            return volume(quantity * 5, density: density, food: food, assumptions: &assumptions)
        case .tablespoon:
            if let specific = food?.tbspGrams { return quantity * specific }
            return volume(quantity * 15, density: density, food: food, assumptions: &assumptions)
        case .cup:
            if let specific = food?.cupGrams { return quantity * specific }
            return volume(quantity * 240, density: density, food: food, assumptions: &assumptions)

        case .piece, .none:
            if let specific = food?.pieceGrams { return quantity * specific }
            assumptions.append(.defaultPieceWeight)
            return quantity * 100
        case .clove: return quantity * 3
        case .slice:
            if let specific = food?.sliceGrams { return quantity * specific }
            assumptions.append(.defaultPieceWeight)
            return quantity * 25
        case .can:
            if let specific = food?.canGrams { return quantity * specific }
            assumptions.append(.defaultPackageSize)
            return quantity * 400
        case .package:
            if let specific = food?.packageGrams { return quantity * specific }
            assumptions.append(.defaultPackageSize)
            return quantity * 250
        case .bunch: return quantity * 25
        case .handful: return quantity * 30
        case .stick:
            if let specific = food?.pieceGrams { return quantity * specific }
            return quantity * 60
        case .cube:
            if let specific = food?.pieceGrams { return quantity * specific }
            return quantity * 10
        case .leaf, .sheet:
            if let specific = food?.pieceGrams { return quantity * specific }
            return quantity * 1.5
        case .pinch: return quantity * 0.3
        case .dash: return quantity * 2
        case .knifeTip: return quantity * 0.5
        case .drop: return quantity * 0.05
        }
    }

    /// Bei Bereichen ("2–3 EL") zählt die Mitte.
    private static func effectiveQuantity(_ measure: Measure) -> Double? {
        guard let lower = measure.quantity else { return nil }
        if let upper = measure.upperBound, upper > lower { return (lower + upper) / 2 }
        return lower
    }

    private static func volume(_ milliliters: Double, density: Double, food: FoodEntry?, assumptions: inout [NutritionEstimate.Assumption]) -> Double {
        // Ohne spezifische Dichte gilt Wasser (1,0) – für Milch, Brühe oder Saft praktisch exakt,
        // bei kalorienreichen Zutaten (Sirup, Nussmus) wird die Annahme vermerkt.
        if let food, food.density == 1.0, food.per100g.calories > 100 {
            assumptions.append(.defaultDensity)
        }
        return milliliters * density
    }
}

/// Liest deklarierte Nährwerte aus Rezepttexten ("Pro Portion: 450 kcal, 30 g Eiweiß, 40 g KH, 15 g Fett").
enum NutritionTextExtractor {
    static func extract(from text: String) -> NutritionFacts? {
        let normalized = text.normalizedForParsing.lowercased()
        // Angaben pro 100 g sind keine Portionswerte → nicht übernehmen
        if normalized.matches(#"(pro|je|per)\s*100\s*g"#) { return nil }

        guard let calories = value(in: normalized, unit: #"(?:kcal|kalorien|calories|cal)"#, allowGram: false) else { return nil }
        guard (20...3000).contains(calories) else { return nil }

        let protein = value(in: normalized, unit: #"(?:eiweiß|eiweiss|protein|proteine)"#, allowGram: true) ?? 0
        let carbs = value(in: normalized, unit: #"(?:kohlenhydrate|kohlenhydrat|carbs|carbohydrates|kh)"#, allowGram: true) ?? 0
        let fat = value(in: normalized, unit: #"(?:fett|fat)"#, allowGram: true) ?? 0

        return NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    /// Findet "30 g Eiweiß", "Eiweiß: 30 g", "30g protein", "Protein 30 g".
    private static func value(in text: String, unit: String, allowGram: Bool) -> Double? {
        let number = #"(\d{1,4}(?:[,.]\d{1,2})?)"#
        let gram = allowGram ? #"[ \t]*g?\b"# : ""
        let patterns = [
            number + #"[ \t]*"# + gram + #"[ \t]*"# + unit + #"\b"#,
            unit + #"[ \t]*[:=]?[ \t]*"# + number + gram
        ]
        for pattern in patterns {
            if let match = text.firstMatch(of: pattern), let raw = match[1],
               let parsed = Double(raw.replacingOccurrences(of: ",", with: ".")) {
                return parsed
            }
        }
        return nil
    }
}
