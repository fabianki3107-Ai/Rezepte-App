import Foundation

/// Formatiert skalierte Mengen so, wie man sie in einem Kochbuch erwartet:
/// "½ TL", "1 ½ Tassen", "250 g", "2–3 EL". Keine "0,333 Zehen".
enum QuantityFormatter {
    /// Bekannte Küchenbrüche mit Unicode-Darstellung.
    private static let fractions: [(value: Double, glyph: String)] = [
        (0.125, "⅛"), (0.25, "¼"), (0.333, "⅓"), (0.5, "½"),
        (0.666, "⅔"), (0.75, "¾")
    ]

    static func string(for measure: Measure, locale: Locale = .current) -> String {
        guard let quantity = measure.quantity else {
            return measure.unit == .none ? "" : measure.unit.symbol
        }
        let lower = number(quantity, unit: measure.unit, locale: locale)
        let amount: String
        if let upper = measure.upperBound, upper > quantity {
            amount = "\(lower)–\(number(upper, unit: measure.unit, locale: locale))"
        } else {
            amount = lower
        }
        let unitText = measure.unit.symbol(for: measure.upperBound ?? quantity)
        return unitText.isEmpty ? amount : "\(amount) \(unitText)"
    }

    /// Formatiert eine einzelne Zahl abhängig vom Einheitentyp.
    static func number(_ value: Double, unit: MeasurementUnit, locale: Locale = .current) -> String {
        if unit.isContinuous {
            return continuous(value, locale: locale)
        }
        return fractional(value, locale: locale)
    }

    /// Gramm/Milliliter: ganze Zahlen, bei großen Mengen auf 5er gerundet.
    private static func continuous(_ value: Double, locale: Locale) -> String {
        let rounded: Double
        switch value {
        case ..<1: rounded = (value * 10).rounded() / 10
        case ..<10: rounded = (value * 2).rounded() / 2   // halbe Schritte: 2,5 g
        case ..<100: rounded = value.rounded()
        default: rounded = (value / 5).rounded() * 5
        }
        return decimal(rounded, maxFractionDigits: 1, locale: locale)
    }

    /// Stückmaße: Brüche snappen, sonst eine Nachkommastelle.
    private static func fractional(_ value: Double, locale: Locale) -> String {
        let whole = value.rounded(.down)
        let remainder = value - whole
        if remainder < 0.06 {
            return decimal(whole, maxFractionDigits: 0, locale: locale)
        }
        if remainder > 0.94 {
            return decimal(whole + 1, maxFractionDigits: 0, locale: locale)
        }
        if let fraction = fractions.first(where: { abs($0.value - remainder) < 0.06 }) {
            return whole == 0 ? fraction.glyph : "\(Int(whole)) \(fraction.glyph)"
        }
        return decimal(value, maxFractionDigits: 1, locale: locale)
    }

    private static func decimal(_ value: Double, maxFractionDigits: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = value >= 10_000
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Reine Skalierungslogik (ohne UI) – Grundlage des Portionen-Skalierers.
struct ServingsScaler: Equatable {
    var baseServings: Int
    var targetServings: Int

    init(baseServings: Int, targetServings: Int? = nil) {
        self.baseServings = max(1, baseServings)
        self.targetServings = max(1, targetServings ?? baseServings)
    }

    var factor: Double { Double(targetServings) / Double(baseServings) }
    var isScaled: Bool { targetServings != baseServings }

    static let range = 1...24

    func scale(_ measure: Measure) -> Measure { measure.scaled(by: factor) }

    mutating func increment() { targetServings = min(Self.range.upperBound, targetServings + 1) }
    mutating func decrement() { targetServings = max(Self.range.lowerBound, targetServings - 1) }
    mutating func reset() { targetServings = baseServings }
}
