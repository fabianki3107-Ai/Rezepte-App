import Foundation
import Testing
@testable import Portio

@Suite("FoodDatabase")
struct FoodDatabaseTests {
    @Test("Deutsche Namen, Plural und Komposita werden zugeordnet")
    func matching() {
        #expect(FoodDatabase.match("Zwiebeln")?.name == "Zwiebel")
        #expect(FoodDatabase.match("2 große Tomaten")?.name == "Tomaten")
        #expect(FoodDatabase.match("Basmatireis")?.name == "Reis")
        #expect(FoodDatabase.match("Knoblauchzehen")?.name == "Knoblauch")
        #expect(FoodDatabase.match("Weizenmehl Type 405")?.name == "Weizenmehl")
        #expect(FoodDatabase.match("frisch gehackte Petersilie")?.name == "Kräuter")
    }

    @Test("Längere Aliase gewinnen vor kürzeren")
    func specificity() {
        #expect(FoodDatabase.match("Tomatenmark")?.name == "Tomatenmark")
        #expect(FoodDatabase.match("stückige Tomaten")?.name == "Dosentomaten")
        #expect(FoodDatabase.match("Paprikapulver")?.name == "Gewürze")
        #expect(FoodDatabase.match("rote Paprika")?.name == "Paprika")
        #expect(FoodDatabase.match("grüne Bohnen")?.name == "Grüne Bohnen")
        #expect(FoodDatabase.match("griechischer Joghurt")?.name == "Griechischer Joghurt")
    }

    @Test("Kurze Aliase treffen nicht in fremden Wörtern")
    func noFalsePositives() {
        #expect(FoodDatabase.match("Preiselbeeren")?.name != "Reis")
        #expect(FoodDatabase.match("Eiweißpulver")?.name == "Proteinpulver")
        #expect(FoodDatabase.match("Zahnstocher") == nil)
    }

    @Test("Englische Namen")
    func english() {
        #expect(FoodDatabase.match("chicken breast")?.name == "Hähnchenbrust")
        #expect(FoodDatabase.match("olive oil")?.name == "Pflanzenöl")
        #expect(FoodDatabase.match("eggs")?.name == "Ei")
    }
}

private func approx(_ value: Double, _ expected: Double, tolerance: Double = 0.01) -> Bool {
    abs(value - expected) <= tolerance
}

@Suite("GramsEstimator")
struct GramsEstimatorTests {
    private func grams(_ quantity: Double?, _ unit: MeasurementUnit, food: String?, upper: Double? = nil) -> (Double, [NutritionEstimate.Assumption]) {
        var assumptions: [NutritionEstimate.Assumption] = []
        let entry = food.flatMap(FoodDatabase.match)
        let result = GramsEstimator.grams(for: Measure(quantity: quantity, upperBound: upper, unit: unit), food: entry, assumptions: &assumptions)
        return (result, assumptions)
    }

    @Test("Gewichte und Volumen")
    func weightsAndVolumes() {
        #expect(grams(250, .gram, food: "Mehl").0 == 250)
        #expect(grams(1, .kilogram, food: "Kartoffeln").0 == 1000)
        #expect(approx(grams(200, .milliliter, food: "Milch").0, 206))   // Dichte 1,03
        #expect(approx(grams(100, .milliliter, food: "Olivenöl").0, 92))  // Dichte 0,92
    }

    @Test("Löffel und Tassen lebensmittelspezifisch")
    func spoonsAndCups() {
        #expect(grams(2, .tablespoon, food: "Olivenöl").0 == 27)
        #expect(grams(1, .teaspoon, food: "Salz").0 == 6)
        #expect(grams(1, .cup, food: "Mehl").0 == 125)
        #expect(grams(1, .cup, food: "Wasser").0 == 240)
    }

    @Test("Stückgewichte und Standardannahmen")
    func pieces() {
        let eggs = grams(4, .piece, food: "Eier")
        #expect(eggs.0 == 220)
        #expect(eggs.1.isEmpty)

        let unknown = grams(2, .none, food: nil)
        #expect(unknown.0 == 200)
        #expect(unknown.1.contains(.defaultPieceWeight))

        let garlic = grams(2, .clove, food: "Knoblauch")
        #expect(garlic.0 == 6)

        let can = grams(1, .can, food: "Kichererbsen")
        #expect(can.0 == 265)
    }

    @Test("Fehlende Menge und Bereiche")
    func missingAndRanges() {
        let missing = grams(nil, .none, food: "Salz")
        #expect(missing.0 == 0)
        #expect(missing.1.contains(.quantityMissing))

        #expect(approx(grams(2, .tablespoon, food: "Olivenöl", upper: 4).0, 40.5)) // Mitte 3 EL × 13,5 g
    }
}

@Suite("LocalNutritionParser")
struct LocalNutritionParserTests {
    private func input(_ name: String, _ quantity: Double?, _ unit: MeasurementUnit, scalable: Bool = true) -> IngredientInput {
        IngredientInput(name: name, measure: Measure(quantity: quantity, upperBound: nil, unit: unit, isScalable: scalable))
    }

    @Test("Shakshuka für 2 Personen liegt in plausiblem Bereich")
    func shakshuka() {
        let ingredients = [
            input("Olivenöl", 2, .tablespoon),
            input("Zwiebel", 1, .piece),
            input("Knoblauch", 2, .clove),
            input("Rote Paprika", 1, .piece),
            input("Stückige Tomaten", 400, .gram),
            input("Kreuzkümmel", 1, .teaspoon),
            input("Eier", 4, .piece),
            input("Feta", 100, .gram),
            input("Salz", nil, .pinch, scalable: false)
        ]
        let estimate = LocalNutritionParser.estimate(ingredients: ingredients, servings: 2)
        #expect(estimate.source == .estimated)
        #expect((380...520).contains(Int(estimate.perServing.calories)))
        #expect(estimate.perServing.protein > 20)
        #expect(estimate.confidence >= NutritionEstimate.goodConfidenceThreshold)
        #expect(estimate.unmatchedNames.isEmpty)
        #expect(estimate.total.calories > estimate.perServing.calories)
    }

    @Test("Unbekannte Zutaten senken die Konfidenz und werden gemeldet")
    func unknownIngredients() {
        let estimate = LocalNutritionParser.estimate(
            ingredients: [input("Mehl", 200, .gram), input("Drachenfruchtpulver", 200, .gram)],
            servings: 1
        )
        #expect(estimate.unmatchedNames == ["Drachenfruchtpulver"])
        #expect(estimate.confidence < 0.6)
        #expect(Int(estimate.perServing.calories) == 728)
    }

    @Test("Deklarierte Nährwerte im Text haben Vorrang")
    func declaredWins() {
        let text = "Nährwerte pro Portion: 450 kcal, 32 g Eiweiß, 40 g Kohlenhydrate, 15 g Fett"
        let estimate = LocalNutritionParser.estimate(ingredients: [input("Mehl", 500, .gram)], servings: 2, rawText: text)
        #expect(estimate.source == .declared)
        #expect(estimate.perServing.calories == 450)
        #expect(estimate.perServing.protein == 32)
        #expect(estimate.perServing.carbs == 40)
        #expect(estimate.perServing.fat == 15)
        #expect(estimate.total.calories == 900)
        #expect(estimate.confidence >= 0.9)
    }

    @Test("Ohne Zutaten keine verwertbare Schätzung")
    func empty() {
        let estimate = LocalNutritionParser.estimate(ingredients: [], servings: 4)
        #expect(!estimate.isUsable)
        #expect(estimate.confidence == 0)
    }
}

@Suite("NutritionTextExtractor")
struct NutritionTextExtractorTests {
    @Test("Verschiedene Schreibweisen")
    func formats() {
        let a = NutritionTextExtractor.extract(from: "Pro Portion: 520 kcal | Protein 38g | KH 45 g | Fett 18g")
        #expect(a?.calories == 520)
        #expect(a?.protein == 38)
        #expect(a?.carbs == 45)
        #expect(a?.fat == 18)

        let b = NutritionTextExtractor.extract(from: "Makros: 35 g Eiweiß · 60 g Carbs · 12 g Fat · 490 Kalorien")
        #expect(b?.calories == 490)
        #expect(b?.protein == 35)
        #expect(b?.carbs == 60)
        #expect(b?.fat == 12)
    }

    @Test("Ohne Kalorienangabe oder pro 100 g wird nichts übernommen")
    func rejects() {
        #expect(NutritionTextExtractor.extract(from: "30 g Eiweiß und 20 g Fett") == nil)
        #expect(NutritionTextExtractor.extract(from: "Pro 100 g: 250 kcal, 10 g Eiweiß") == nil)
        #expect(NutritionTextExtractor.extract(from: "10 Minuten köcheln lassen") == nil)
    }
}

@Suite("NutritionFacts & Goals")
struct NutritionFactsTests {
    @Test("Addition, Skalierung, Rundung")
    func arithmetic() {
        let a = NutritionFacts(calories: 100, protein: 10, carbs: 5, fat: 2)
        let b = NutritionFacts(calories: 50.4, protein: 1.26, carbs: 2.55, fat: 0.04)
        let sum = (a + b).rounded()
        #expect(sum.calories == 150)
        #expect(approx(sum.protein, 11.3))
        #expect(approx(sum.carbs, 7.6))
        #expect(approx(sum.fat, 2))
        #expect(approx(a.scaled(by: 1.5).calories, 150))
        #expect(approx(a.caloriesFromMacros, 78))
    }

    @Test("Mahlzeit nach Uhrzeit")
    func mealGuess() {
        var components = DateComponents(year: 2026, month: 10, day: 21, hour: 8)
        let calendar = Calendar(identifier: .gregorian)
        #expect(MealSlot.guess(for: calendar.date(from: components)!, calendar: calendar) == .breakfast)
        components.hour = 13
        #expect(MealSlot.guess(for: calendar.date(from: components)!, calendar: calendar) == .lunch)
        components.hour = 19
        #expect(MealSlot.guess(for: calendar.date(from: components)!, calendar: calendar) == .dinner)
        components.hour = 16
        #expect(MealSlot.guess(for: calendar.date(from: components)!, calendar: calendar) == .snack)
    }

    @Test("Ziele: Kalorien aus Makros")
    func goals() {
        let goals = NutritionGoals(calories: 2000, protein: 120, carbs: 230, fat: 70)
        #expect(goals.caloriesFromMacroGoals == 120 * 4 + 230 * 4 + 70 * 9)
        #expect(goals.goal(for: .protein) == 120)
    }
}
