import Foundation

/// Beispieldaten für Previews, UI-Tests und den ersten App-Start.
extension Recipe {
    static func sampleRecipes() -> [Recipe] {
        [sampleShakshuka(), samplePancakes()]
    }

    static func sampleShakshuka() -> Recipe {
        let recipe = Recipe(
            title: "Shakshuka mit Feta",
            summary: "Würzige Tomaten-Paprika-Pfanne mit pochierten Eiern – in 30 Minuten auf dem Tisch.",
            servings: 2,
            prepTimeMinutes: 10,
            cookTimeMinutes: 20,
            difficulty: .easy,
            source: .instagram(URL(string: "https://www.instagram.com/p/C1a2B3c4D5e/")!),
            sourceAuthor: "@kochliebe",
            ocrConfidence: 0.93,
            verification: .userVerified,
            isFavorite: true
        )
        recipe.ingredients = [
            Ingredient(sortIndex: 0, name: "Olivenöl", quantity: 2, unit: .tablespoon),
            Ingredient(sortIndex: 1, name: "Zwiebel", quantity: 1, unit: .piece, note: "fein gewürfelt"),
            Ingredient(sortIndex: 2, name: "Knoblauch", quantity: 2, unit: .clove),
            Ingredient(sortIndex: 3, name: "Rote Paprika", quantity: 1, unit: .piece),
            Ingredient(sortIndex: 4, name: "Stückige Tomaten", quantity: 400, unit: .gram),
            Ingredient(sortIndex: 5, name: "Kreuzkümmel", quantity: 1, unit: .teaspoon),
            Ingredient(sortIndex: 6, name: "Paprikapulver", quantity: 1, unit: .teaspoon),
            Ingredient(sortIndex: 7, name: "Eier", quantity: 4, unit: .piece),
            Ingredient(sortIndex: 8, name: "Feta", quantity: 100, unit: .gram),
            Ingredient(sortIndex: 9, name: "Salz", unit: .pinch, isScalable: false),
            Ingredient(sortIndex: 10, name: "Petersilie", note: "zum Servieren", isScalable: false, isOptional: true)
        ]
        recipe.steps = [
            CookingStep(sortIndex: 0, text: "Olivenöl in einer Pfanne erhitzen. Zwiebel und Paprika darin 5 Minuten anschwitzen.", durationSeconds: 300),
            CookingStep(sortIndex: 1, text: "Knoblauch, Kreuzkümmel und Paprikapulver zugeben und kurz mitrösten."),
            CookingStep(sortIndex: 2, text: "Tomaten unterrühren, salzen und 10 Minuten offen köcheln lassen.", durationSeconds: 600),
            CookingStep(sortIndex: 3, text: "Mit einem Löffel vier Mulden formen, je ein Ei hineingleiten lassen. Deckel auflegen und 6 Minuten pochieren.", durationSeconds: 360),
            CookingStep(sortIndex: 4, text: "Feta darüberbröseln, mit Petersilie bestreuen und direkt aus der Pfanne servieren.")
        ]
        return recipe
    }

    static func samplePancakes() -> Recipe {
        let recipe = Recipe(
            title: "Fluffige Pancakes",
            summary: "Amerikanische Pancakes mit Buttermilch.",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            difficulty: .easy,
            source: .screenshot,
            ocrConfidence: 0.78
        )
        recipe.ingredients = [
            Ingredient(sortIndex: 0, name: "Mehl", quantity: 250, unit: .gram, group: "Teig"),
            Ingredient(sortIndex: 1, name: "Zucker", quantity: 2, unit: .tablespoon, group: "Teig"),
            Ingredient(sortIndex: 2, name: "Backpulver", quantity: 2, unit: .teaspoon, group: "Teig"),
            Ingredient(sortIndex: 3, name: "Buttermilch", quantity: 350, unit: .milliliter, group: "Teig"),
            Ingredient(sortIndex: 4, name: "Eier", quantity: 2, unit: .piece, group: "Teig"),
            Ingredient(sortIndex: 5, name: "Butter", quantity: 30, unit: .gram, note: "geschmolzen", group: "Teig"),
            Ingredient(sortIndex: 6, name: "Ahornsirup", group: "Zum Servieren", isScalable: false),
            Ingredient(sortIndex: 7, name: "Blaubeeren", quantity: 1, unit: .handful, group: "Zum Servieren")
        ]
        recipe.steps = [
            CookingStep(sortIndex: 0, text: "Mehl, Zucker und Backpulver in einer Schüssel vermengen."),
            CookingStep(sortIndex: 1, text: "Buttermilch, Eier und geschmolzene Butter verquirlen und nur kurz unter die trockenen Zutaten rühren. Teig 5 Minuten ruhen lassen.", durationSeconds: 300),
            CookingStep(sortIndex: 2, text: "Pfanne bei mittlerer Hitze erwärmen, je eine kleine Kelle Teig hineingeben und 2 Minuten backen, bis Blasen entstehen. Wenden und 1 Minute fertig backen.", durationSeconds: 120),
            CookingStep(sortIndex: 3, text: "Mit Ahornsirup und Blaubeeren servieren.")
        ]
        return recipe
    }
}
