import Foundation

/// Zwischenergebnis eines Imports – noch kein SwiftData-Objekt.
/// Der Nutzer prüft und korrigiert den Entwurf in `ImportReviewView`, erst dann wird gespeichert.
struct ParsedRecipeDraft: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var summary: String?
    var notes: String?
    var servings: Int?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var ingredients: [DraftIngredient]
    var steps: [DraftStep]
    var tags: [String]
    var source: ImportSource
    var sourceAuthor: String?
    /// Mittlere OCR-Konfidenz (0...1); nil bei Text-Import.
    var ocrConfidence: Double?
    var heroImageData: Data?
    var rawText: String
    var warnings: [Warning]

    enum Warning: Hashable, Identifiable {
        case noIngredientsFound
        case noStepsFound
        case lowConfidence(Double)
        case servingsGuessed
        case captionUnavailable

        var id: String {
            switch self {
            case .noIngredientsFound: return "noIngredients"
            case .noStepsFound: return "noSteps"
            case .lowConfidence: return "lowConfidence"
            case .servingsGuessed: return "servingsGuessed"
            case .captionUnavailable: return "captionUnavailable"
            }
        }

        var message: String {
            switch self {
            case .noIngredientsFound:
                return "Es wurden keine Zutaten erkannt. Bitte ergänze sie manuell."
            case .noStepsFound:
                return "Es wurden keine Zubereitungsschritte erkannt."
            case .lowConfidence(let value):
                return "Die Texterkennung war unsicher (\(Int(value * 100)) %). Bitte Mengen prüfen."
            case .servingsGuessed:
                return "Die Portionszahl wurde nicht gefunden und auf 4 gesetzt."
            case .captionUnavailable:
                return "Der Instagram-Text konnte nicht geladen werden. Füge ihn ein oder importiere einen Screenshot."
            }
        }

        var isBlocking: Bool {
            switch self {
            case .noIngredientsFound, .captionUnavailable: return true
            default: return false
            }
        }
    }

    /// Alles, was der Nutzer mindestens braucht, um sinnvoll zu speichern.
    var isSaveable: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (!ingredients.isEmpty || !steps.isEmpty)
    }

    static func empty(source: ImportSource = .manual) -> ParsedRecipeDraft {
        ParsedRecipeDraft(
            title: "", summary: nil, notes: nil, servings: 4, prepTimeMinutes: nil, cookTimeMinutes: nil,
            ingredients: [], steps: [], tags: [], source: source, sourceAuthor: nil,
            ocrConfidence: nil, heroImageData: nil, rawText: "", warnings: []
        )
    }
}

struct DraftIngredient: Identifiable, Hashable {
    var id = UUID()
    var rawLine: String
    var name: String
    var quantity: Double?
    var quantityUpperBound: Double?
    var unit: MeasurementUnit
    var note: String?
    var group: String?
    var isScalable: Bool
    var isOptional: Bool

    var measure: Measure {
        Measure(quantity: quantity, upperBound: quantityUpperBound, unit: unit, isScalable: isScalable)
    }

    /// Einzeilige Darstellung für Listen und Textfelder.
    var displayText: String {
        let amount = QuantityFormatter.string(for: measure)
        var parts: [String] = []
        if !amount.isEmpty { parts.append(amount) }
        parts.append(name)
        if let note, !note.isEmpty { parts.append("(\(note))") }
        return parts.joined(separator: " ")
    }

    /// Erzeugt eine Zutat aus freiem Text (Bearbeitung im Review oder manuelle Eingabe).
    static func from(line: String, group: String? = nil) -> DraftIngredient? {
        guard let parsed = IngredientLineParser.parse(line) else { return nil }
        return DraftIngredient(
            rawLine: line,
            name: parsed.name,
            quantity: parsed.quantity,
            quantityUpperBound: parsed.upperBound,
            unit: parsed.unit,
            note: parsed.note,
            group: group,
            isScalable: parsed.isScalable,
            isOptional: parsed.isOptional
        )
    }
}

struct DraftStep: Identifiable, Hashable {
    var id = UUID()
    var text: String
    var durationSeconds: Int?
    var temperatureCelsius: Int?

    static func from(text: String) -> DraftStep {
        let annotations = StepAnnotator.annotate(text)
        return DraftStep(text: text, durationSeconds: annotations.durationSeconds, temperatureCelsius: annotations.temperatureCelsius)
    }
}
