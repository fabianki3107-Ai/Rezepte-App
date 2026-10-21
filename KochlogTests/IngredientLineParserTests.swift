import Testing
@testable import Kochlog

@Suite("IngredientLineParser")
struct IngredientLineParserTests {
    @Test("Standardzeile mit Menge, Einheit und Name")
    func basicLine() throws {
        let result = try #require(IngredientLineParser.parse("200 g Mehl"))
        #expect(result.quantity == 200)
        #expect(result.unit == .gram)
        #expect(result.name == "Mehl")
        #expect(result.isScalable)
    }

    @Test("Einheit ohne Leerzeichen und Kommazahl")
    func attachedUnit() throws {
        let result = try #require(IngredientLineParser.parse("1,5l Milch"))
        #expect(result.quantity == 1.5)
        #expect(result.unit == .liter)
        #expect(result.name == "Milch")
    }

    @Test("Unicode-Bruch und gemischte Zahl")
    func fractions() throws {
        let half = try #require(IngredientLineParser.parse("½ TL Salz"))
        #expect(half.quantity == 0.5)
        #expect(half.unit == .teaspoon)

        let mixed = try #require(IngredientLineParser.parse("1 ½ Tassen Zucker"))
        #expect(mixed.quantity == 1.5)
        #expect(mixed.unit == .cup)

        let slash = try #require(IngredientLineParser.parse("1 1/2 EL Honig"))
        #expect(slash.quantity == 1.5)
        #expect(slash.unit == .tablespoon)
    }

    @Test("Bereichsangabe 2–3 EL")
    func range() throws {
        let result = try #require(IngredientLineParser.parse("2-3 EL Olivenöl"))
        #expect(result.quantity == 2)
        #expect(result.upperBound == 3)
        #expect(result.unit == .tablespoon)
        #expect(result.name == "Olivenöl")
    }

    @Test("Hinweis nach Komma und in Klammern")
    func notes() throws {
        let comma = try #require(IngredientLineParser.parse("1 Zwiebel, fein gewürfelt"))
        #expect(comma.name == "Zwiebel")
        #expect(comma.note == "fein gewürfelt")
        #expect(comma.unit == .none)

        let parens = try #require(IngredientLineParser.parse("1 Dose Tomaten (400 g)"))
        #expect(parens.unit == .can)
        #expect(parens.name == "Tomaten")
        #expect(parens.note == "400 g")
    }

    @Test("Optional-Markierung wird erkannt und entfernt")
    func optional() throws {
        let result = try #require(IngredientLineParser.parse("Petersilie zum Servieren (optional)"))
        #expect(result.isOptional)
        #expect(result.quantity == nil)
        #expect(!result.isScalable)
        #expect(result.name == "Petersilie zum Servieren")
    }

    @Test("Zahlwort und Prise")
    func wordsAndPinch() throws {
        let word = try #require(IngredientLineParser.parse("zwei Knoblauchzehen"))
        #expect(word.quantity == 2)
        #expect(word.name == "Knoblauchzehen")

        let pinch = try #require(IngredientLineParser.parse("Prise Muskat"))
        #expect(pinch.unit == .pinch)
        #expect(pinch.quantity == 1)
        #expect(!pinch.isScalable)
    }

    @Test("Aufzählungszeichen und Emojis werden ignoriert")
    func bullets() throws {
        let result = try #require(IngredientLineParser.parse("• 🥚 4 Eier"))
        #expect(result.quantity == 4)
        #expect(result.name == "Eier")
    }

    @Test("Tabellen-Layout 'Mehl 250 g' aus zweispaltiger OCR")
    func trailingQuantity() throws {
        let result = try #require(IngredientLineParser.parse("Mehl 250 g"))
        #expect(result.quantity == 250)
        #expect(result.unit == .gram)
        #expect(result.name == "Mehl")
    }

    @Test("Multiplikator 2x 400 g")
    func multiplier() throws {
        let result = try #require(IngredientLineParser.parse("2 x 400 g stückige Tomaten"))
        #expect(result.quantity == 800)
        #expect(result.unit == .gram)
    }

    @Test("Gestrichener Teelöffel")
    func modifier() throws {
        let result = try #require(IngredientLineParser.parse("1 gestr. TL Backpulver"))
        #expect(result.unit == .teaspoon)
        #expect(result.name == "Backpulver")
    }

    @Test("Zeile ohne Buchstaben liefert nil")
    func garbage() {
        #expect(IngredientLineParser.parse("---") == nil)
        #expect(IngredientLineParser.parse("12:34") == nil)
    }
}
