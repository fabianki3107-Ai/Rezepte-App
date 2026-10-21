import Foundation
import Testing
@testable import Kochlog

@Suite("QuantityFormatter & ServingsScaler")
struct QuantityFormatterTests {
    let german = Locale(identifier: "de_DE")

    @Test("Stückmaße werden als Brüche dargestellt")
    func fractions() {
        #expect(QuantityFormatter.string(for: Measure(quantity: 0.5, upperBound: nil, unit: .teaspoon), locale: german) == "½ TL")
        #expect(QuantityFormatter.string(for: Measure(quantity: 1.5, upperBound: nil, unit: .cup), locale: german) == "1 ½ Tassen")
        #expect(QuantityFormatter.string(for: Measure(quantity: 0.333, upperBound: nil, unit: .piece), locale: german) == "⅓ Stück")
        #expect(QuantityFormatter.string(for: Measure(quantity: 2.98, upperBound: nil, unit: .piece), locale: german) == "3 Stück")
    }

    @Test("Kontinuierliche Einheiten werden sinnvoll gerundet")
    func continuous() {
        #expect(QuantityFormatter.string(for: Measure(quantity: 333.3, upperBound: nil, unit: .gram), locale: german) == "335 g")
        #expect(QuantityFormatter.string(for: Measure(quantity: 62.5, upperBound: nil, unit: .milliliter), locale: german) == "63 ml")
        #expect(QuantityFormatter.string(for: Measure(quantity: 2.5, upperBound: nil, unit: .gram), locale: german) == "2,5 g")
        #expect(QuantityFormatter.string(for: Measure(quantity: 0.75, upperBound: nil, unit: .liter), locale: german) == "0,8 l")
    }

    @Test("Bereiche und Plural")
    func rangesAndPlural() {
        #expect(QuantityFormatter.string(for: Measure(quantity: 2, upperBound: 3, unit: .tablespoon), locale: german) == "2–3 EL")
        #expect(QuantityFormatter.string(for: Measure(quantity: 2, upperBound: nil, unit: .clove), locale: german) == "2 Zehen")
        #expect(QuantityFormatter.string(for: Measure(quantity: 1, upperBound: nil, unit: .clove), locale: german) == "1 Zehe")
    }

    @Test("Ohne Menge nur Einheit oder leer")
    func missingQuantity() {
        #expect(QuantityFormatter.string(for: Measure(quantity: nil, upperBound: nil, unit: .none), locale: german) == "")
        #expect(QuantityFormatter.string(for: Measure(quantity: nil, upperBound: nil, unit: .pinch), locale: german) == "Prise")
    }

    @Test("Skalierung verdoppelt skalierbare Mengen, lässt Gewürze unberührt")
    func scaling() {
        let scaler = ServingsScaler(baseServings: 2, targetServings: 4)
        #expect(scaler.factor == 2)
        let flour = Measure(quantity: 250, upperBound: nil, unit: .gram)
        #expect(scaler.scale(flour).quantity == 500)
        let salt = Measure(quantity: 1, upperBound: nil, unit: .pinch, isScalable: false)
        #expect(scaler.scale(salt).quantity == 1)
        let range = Measure(quantity: 2, upperBound: 3, unit: .tablespoon)
        #expect(scaler.scale(range).upperBound == 6)
    }

    @Test("Grenzen des Skalierers")
    func bounds() {
        var scaler = ServingsScaler(baseServings: 4, targetServings: 1)
        scaler.decrement()
        #expect(scaler.targetServings == 1)
        scaler.targetServings = ServingsScaler.range.upperBound
        scaler.increment()
        #expect(scaler.targetServings == ServingsScaler.range.upperBound)
        scaler.reset()
        #expect(scaler.targetServings == 4)
        #expect(!scaler.isScaled)
    }

    @Test("Ungültige Basis wird auf 1 angehoben")
    func invalidBase() {
        let scaler = ServingsScaler(baseServings: 0)
        #expect(scaler.baseServings == 1)
        #expect(scaler.targetServings == 1)
    }
}

@Suite("DurationFormatting")
struct DurationFormattingTests {
    @Test func shortForm() {
        #expect(DurationFormatting.short(45) == "45 Sek")
        #expect(DurationFormatting.short(360) == "6 Min")
        #expect(DurationFormatting.short(3600) == "1 Std")
        #expect(DurationFormatting.short(4200) == "1 Std 10 Min")
    }

    @Test func clockForm() {
        #expect(DurationFormatting.clock(275) == "04:35")
        #expect(DurationFormatting.clock(3725) == "1:02:05")
        #expect(DurationFormatting.clock(-3) == "00:00")
    }
}
