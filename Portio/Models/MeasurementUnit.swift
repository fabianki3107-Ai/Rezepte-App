import Foundation

/// Maßeinheiten mit deutschen und englischen Schreibweisen für Parser und Anzeige.
enum MeasurementUnit: String, Codable, CaseIterable, Identifiable {
    case none
    // Gewicht
    case gram, kilogram, pound, ounce
    // Volumen
    case milliliter, centiliter, deciliter, liter
    case teaspoon, tablespoon, cup
    // Stückzahlen / Küchenmaße
    case piece, pinch, dash, handful, bunch, clove, can, package, slice, stick, leaf, cube, drop, sheet, knifeTip

    var id: String { rawValue }

    /// Kurzform für die Anzeige (deutsch).
    var symbol: String {
        switch self {
        case .none: return ""
        case .gram: return "g"
        case .kilogram: return "kg"
        case .pound: return "Pfd."
        case .ounce: return "oz"
        case .milliliter: return "ml"
        case .centiliter: return "cl"
        case .deciliter: return "dl"
        case .liter: return "l"
        case .teaspoon: return "TL"
        case .tablespoon: return "EL"
        case .cup: return "Tasse"
        case .piece: return "Stück"
        case .pinch: return "Prise"
        case .dash: return "Spritzer"
        case .handful: return "Handvoll"
        case .bunch: return "Bund"
        case .clove: return "Zehe"
        case .can: return "Dose"
        case .package: return "Pck."
        case .slice: return "Scheibe"
        case .stick: return "Stange"
        case .leaf: return "Blatt"
        case .cube: return "Würfel"
        case .drop: return "Tropfen"
        case .sheet: return "Bogen"
        case .knifeTip: return "Msp."
        }
    }

    /// Pluralform, wo sie sich von der Kurzform unterscheidet.
    func symbol(for quantity: Double?) -> String {
        guard let quantity, quantity > 1 else { return symbol }
        switch self {
        case .cup: return "Tassen"
        case .pinch: return "Prisen"
        case .clove: return "Zehen"
        case .can: return "Dosen"
        case .slice: return "Scheiben"
        case .stick: return "Stangen"
        case .leaf: return "Blätter"
        case .cube: return "Würfel"
        case .sheet: return "Bögen"
        default: return symbol
        }
    }

    /// Kontinuierliche Einheiten werden auf ganze Zahlen gerundet, Stückmaße in Bruchteilen dargestellt.
    var isContinuous: Bool {
        switch self {
        case .gram, .kilogram, .milliliter, .centiliter, .deciliter, .liter, .ounce, .pound: return true
        default: return false
        }
    }

    /// Einheiten, die typischerweise "nach Geschmack" sind und nicht sinnvoll skalieren.
    var defaultsToUnscalable: Bool {
        switch self {
        case .pinch, .dash, .knifeTip, .drop: return true
        default: return false
        }
    }

    /// Alle akzeptierten Schreibweisen (kleingeschrieben, ohne Punkt) → Einheit.
    /// Längere Aliase werden vom Parser zuerst geprüft.
    static let aliases: [String: MeasurementUnit] = {
        let table: [MeasurementUnit: [String]] = [
            .gram: ["g", "gr", "gramm", "gram", "grams"],
            .kilogram: ["kg", "kilo", "kilogramm", "kilogram", "kilograms"],
            .pound: ["pfund", "pfd", "lb", "lbs", "pound", "pounds"],
            .ounce: ["oz", "unze", "unzen", "ounce", "ounces"],
            .milliliter: ["ml", "milliliter", "millilitre", "milliliters"],
            .centiliter: ["cl", "zentiliter"],
            .deciliter: ["dl", "deziliter"],
            .liter: ["l", "liter", "litre", "liters", "ltr"],
            .teaspoon: ["tl", "teelöffel", "teeloeffel", "tsp", "teaspoon", "teaspoons"],
            .tablespoon: ["el", "esslöffel", "essloeffel", "tbsp", "tbs", "tablespoon", "tablespoons"],
            .cup: ["tasse", "tassen", "cup", "cups", "becher"],
            .piece: ["stück", "stueck", "stk", "st", "piece", "pieces", "pc", "pcs"],
            .pinch: ["prise", "prisen", "pinch"],
            .dash: ["spritzer", "schuss", "dash", "splash"],
            .handful: ["handvoll", "handful"],
            .bunch: ["bund", "bündel", "bunch"],
            .clove: ["zehe", "zehen", "knoblauchzehe", "knoblauchzehen", "clove", "cloves"],
            .can: ["dose", "dosen", "can", "cans", "tin"],
            .package: ["packung", "packungen", "pck", "pkg", "päckchen", "paeckchen", "pack", "package", "beutel"],
            .slice: ["scheibe", "scheiben", "slice", "slices"],
            .stick: ["stange", "stangen", "stick", "sticks"],
            .leaf: ["blatt", "blätter", "blaetter", "leaf", "leaves"],
            .cube: ["würfel", "wuerfel", "cube", "cubes"],
            .drop: ["tropfen", "drop", "drops"],
            .sheet: ["bogen", "bögen", "sheet", "sheets"],
            .knifeTip: ["msp", "messerspitze", "messerspitzen"]
        ]
        var result: [String: MeasurementUnit] = [:]
        for (unit, names) in table {
            for name in names { result[name] = unit }
        }
        return result
    }()

    static func match(_ token: String) -> MeasurementUnit? {
        let key = token.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)
        return aliases[key]
    }
}
