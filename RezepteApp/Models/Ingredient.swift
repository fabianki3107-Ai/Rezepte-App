import Foundation
import SwiftData

/// Eine Zutat mit strukturierter Menge, damit Portionen skaliert werden können.
@Model
final class Ingredient {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var name: String
    /// Menge in `unit`; `nil` bedeutet "nach Geschmack" / ohne Angabe.
    var quantity: Double?
    /// Obergrenze bei Bereichsangaben wie "2–3 EL".
    var quantityUpperBound: Double?
    var unitRaw: String
    /// Zubereitungs-Hinweis, z. B. "fein gewürfelt".
    var note: String?
    /// Gruppenüberschrift wie "Für den Teig".
    var group: String?
    /// Zutaten wie Salz oder Öl zum Braten werden nicht mitskaliert.
    var isScalable: Bool
    var isOptional: Bool
    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        sortIndex: Int,
        name: String,
        quantity: Double? = nil,
        quantityUpperBound: Double? = nil,
        unit: MeasurementUnit = .none,
        note: String? = nil,
        group: String? = nil,
        isScalable: Bool = true,
        isOptional: Bool = false
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.name = name
        self.quantity = quantity
        self.quantityUpperBound = quantityUpperBound
        self.unitRaw = unit.rawValue
        self.note = note
        self.group = group
        self.isScalable = isScalable
        self.isOptional = isOptional
    }

    var unit: MeasurementUnit {
        get { MeasurementUnit(rawValue: unitRaw) ?? .none }
        set { unitRaw = newValue.rawValue }
    }

    /// Reine Wert-Repräsentation für Skalierung und Formatierung (ohne SwiftData-Abhängigkeit).
    var measure: Measure {
        Measure(quantity: quantity, upperBound: quantityUpperBound, unit: unit, isScalable: isScalable)
    }
}

/// Schlanker Werttyp für Mengenlogik – testbar ohne ModelContext.
struct Measure: Hashable {
    var quantity: Double?
    var upperBound: Double?
    var unit: MeasurementUnit
    var isScalable: Bool = true

    func scaled(by factor: Double) -> Measure {
        guard isScalable, factor > 0 else { return self }
        return Measure(
            quantity: quantity.map { $0 * factor },
            upperBound: upperBound.map { $0 * factor },
            unit: unit,
            isScalable: isScalable
        )
    }
}
