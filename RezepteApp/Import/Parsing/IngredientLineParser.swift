import Foundation

/// Zerlegt eine einzelne Zutatenzeile wie "2 ½ EL Olivenöl, kaltgepresst (optional)"
/// in Menge, Einheit, Name und Hinweis. Rein funktional, deterministisch, testbar.
enum IngredientLineParser {
    struct Output: Hashable {
        var name: String
        var quantity: Double?
        var upperBound: Double?
        var unit: MeasurementUnit
        var note: String?
        var isOptional: Bool
        var isScalable: Bool
        /// Ob eine (numerische oder textuelle) Mengenangabe gefunden wurde – wichtig für die Zeilen-Klassifikation.
        var hadQuantity: Bool
    }

    private static let fractionGlyphs: [Character: Double] = [
        "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75,
        "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875, "⅕": 0.2, "⅙": 1.0 / 6
    ]

    private static let numberWords: [String: Double] = [
        "ein": 1, "eine": 1, "einen": 1, "einer": 1, "einem": 1,
        "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8,
        "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12,
        "halbe": 0.5, "halben": 0.5, "halber": 0.5, "eineinhalb": 1.5, "anderthalb": 1.5,
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "half": 0.5
    ]

    /// Formulierungen ohne echte Menge – die Zutat wird nicht mitskaliert.
    private static let vaguePhrases = [
        "etwas", "einige", "ein paar", "nach geschmack", "nach belieben", "n. b.", "n.b.",
        "bei bedarf", "zum braten", "zum servieren", "zum bestreuen", "zum garnieren",
        "to taste", "some", "a little", "a few", "as needed", "for frying", "for serving"
    ]

    /// Adjektive vor Einheiten, die übersprungen werden: "1 gestr. TL", "2 geh. EL".
    private static let unitModifiers: Set<String> = [
        "gestr", "gestrichener", "gestrichene", "gestrichen", "geh", "gehäufter", "gehäufte", "gehäuft",
        "level", "heaped", "heaping", "großer", "große", "großes", "kleiner", "kleine", "kleines", "voller", "volle"
    ]

    private static let fractionClass = "[½⅓⅔¼¾⅛⅜⅝⅞⅕⅙]"
    private static let numberAtom = #"(?:\d+\s+\d+\s*/\s*\d+|\d+\s*/\s*\d+|\d+\s*"# + fractionClass + #"|\d+(?:[.,]\d+)?|"# + fractionClass + ")"
    private static let leadingQuantityPattern = "^(" + numberAtom + #")(?:\s*(?:-|–|—|bis|to)\s*("# + numberAtom + #"))?\s*(.*)$"#
    private static let trailingQuantityPattern = #"^(.*?\p{L})\s+("# + numberAtom + #")\s*(\p{L}{1,12}\.?)?\s*$"#
    private static let multiplierPattern = #"^(?:x|×)\s*(\d+(?:[.,]\d+)?)\s*(.*)$"#
    private static let leadingWordPattern = #"^(\p{L}+\.?)(?:\s+|$)(.*)$"#

    // MARK: - API

    static func parse(_ rawLine: String) -> Output? {
        var line = stripBullet(rawLine.normalizedForParsing.removingEmoji.collapsingWhitespace)
        guard !line.isEmpty, line.rangeOfCharacter(from: .letters) != nil else { return nil }

        var isOptional = false
        if line.matches(#"\(\s*optional\s*\)|\boptional\b"#) {
            isOptional = true
            line = line.replacingMatches(of: #"\(\s*optional\s*\)|,?\s*\boptional\b"#, with: "").collapsingWhitespace
        }

        var quantity: Double?
        var upperBound: Double?
        var rest = line
        var hadQuantity = false

        if let match = line.firstMatch(of: leadingQuantityPattern), let lower = match[1].flatMap(parseNumber) {
            quantity = lower
            upperBound = match[2].flatMap(parseNumber)
            rest = match[3] ?? ""
            hadQuantity = true
            if let multiplier = rest.firstMatch(of: multiplierPattern), let factor = multiplier[1].flatMap(parseNumber) {
                quantity = lower * factor
                upperBound = upperBound.map { $0 * factor }
                rest = multiplier[2] ?? ""
            }
        } else if let match = line.firstMatch(of: leadingWordPattern),
                  let word = match[1]?.lowercased().replacingOccurrences(of: ".", with: ""),
                  let value = numberWords[word] {
            quantity = value
            rest = match[2] ?? ""
            hadQuantity = true
        }

        var unit = MeasurementUnit.none
        if let (parsedUnit, remainder) = parseLeadingUnit(rest) {
            unit = parsedUnit
            rest = remainder
            if quantity == nil {
                quantity = 1 // "Prise Salz" → 1 Prise
            }
        } else if quantity == nil, let match = line.firstMatch(of: trailingQuantityPattern),
                  let value = match[2].flatMap(parseNumber) {
            // Tabellen-Layout "Mehl 250 g" (häufig nach OCR zweispaltiger Zutatenlisten)
            let unitToken = match[3] ?? ""
            let trailingUnit = MeasurementUnit.match(unitToken)
            if trailingUnit != nil || unitToken.isEmpty {
                quantity = value
                unit = trailingUnit ?? .none
                rest = match[1] ?? ""
                hadQuantity = true
            }
        }

        let lowercased = rest.lowercased()
        var isScalable = quantity != nil
        if unit.defaultsToUnscalable || vaguePhrases.contains(where: { lowercased.contains($0) }) {
            isScalable = false
        }

        let (name, note) = splitNameAndNote(rest)
        guard !name.isEmpty else { return nil }

        return Output(
            name: name,
            quantity: quantity,
            upperBound: upperBound,
            unit: unit,
            note: note,
            isOptional: isOptional,
            isScalable: isScalable,
            hadQuantity: hadQuantity
        )
    }

    /// Grobe Klassifikation für den Abschnitts-Erkenner: sieht die Zeile wie eine Zutat aus?
    static func looksLikeIngredient(_ line: String) -> Bool {
        guard let parsed = parse(line) else { return false }
        let words = line.wordCount
        guard words <= 12 else { return false }
        if parsed.hadQuantity || parsed.unit != .none { return true }
        // Kurze Zeilen ohne Menge ("Salz", "Pfeffer aus der Mühle") zählen nur in Zutaten-Kontext
        return false
    }

    // MARK: - Bausteine

    static func stripBullet(_ line: String) -> String {
        var scalars = Substring(line).unicodeScalars[...]
        while let first = scalars.first {
            let isBulletLike = !(first.properties.isAlphabetic || CharacterSet.decimalDigits.contains(first)
                                 || fractionGlyphs.keys.contains(Character(first)) || first == "(" )
            if isBulletLike { scalars = scalars.dropFirst() } else { break }
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
    }

    static func parseNumber(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // "1 ½" oder "1½"
        if let glyph = text.last, let fraction = fractionGlyphs[glyph] {
            let prefix = text.dropLast().trimmingCharacters(in: .whitespaces)
            if prefix.isEmpty { return fraction }
            return Double(prefix.replacingOccurrences(of: ",", with: ".")).map { $0 + fraction }
        }
        // "1 1/2" oder "1/2"
        if text.contains("/") {
            let parts = text.split(separator: " ", omittingEmptySubsequences: true)
            var whole = 0.0
            var fractionText = text
            if parts.count == 2, let w = Double(parts[0]) {
                whole = w
                fractionText = String(parts[1])
            }
            let components = fractionText.replacingOccurrences(of: " ", with: "").split(separator: "/")
            guard components.count == 2,
                  let numerator = Double(components[0]),
                  let denominator = Double(components[1]), denominator != 0 else { return nil }
            return whole + numerator / denominator
        }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func parseLeadingUnit(_ text: String) -> (MeasurementUnit, String)? {
        var remaining = text
        var consumedModifier = false
        for _ in 0..<2 {
            guard let match = remaining.firstMatch(of: leadingWordPattern), let token = match[1] else { return nil }
            let cleaned = token.lowercased().replacingOccurrences(of: ".", with: "")
            if let unit = MeasurementUnit.match(cleaned) {
                let remainder = (match[2] ?? "").trimmingCharacters(in: .whitespaces)
                // "2 Knoblauchzehen" ist eine Zutat, kein Maß ohne Namen
                guard !remainder.isEmpty else { return nil }
                return (unit, remainder)
            }
            if unitModifiers.contains(cleaned), !consumedModifier {
                consumedModifier = true
                remaining = match[2] ?? ""
                continue
            }
            return nil
        }
        return nil
    }

    private static func splitNameAndNote(_ text: String) -> (name: String, note: String?) {
        var working = text
        var notes: [String] = []

        for match in working.allMatches(of: #"\(([^)]*)\)"#) {
            if let inner = match[1]?.trimmedPunctuation, !inner.isEmpty { notes.append(inner) }
        }
        working = working.replacingMatches(of: #"\([^)]*\)"#, with: " ").collapsingWhitespace

        // "Zwiebel, fein gewürfelt" / "Butter – zimmerwarm"
        if let range = working.range(of: #"\s*(?:,|;|\s[-–—]\s)\s*"#, options: .regularExpression) {
            let head = String(working[..<range.lowerBound])
            let tail = String(working[range.upperBound...]).trimmedPunctuation
            if !head.trimmedPunctuation.isEmpty {
                working = head
                if !tail.isEmpty { notes.insert(tail, at: 0) }
            }
        }

        working = working.replacingMatches(of: #"^(?:of|von|an)\s+"#, with: "")
        let name = working.trimmedPunctuation.collapsingWhitespace.capitalizingFirstLetter
        let note = notes.isEmpty ? nil : notes.joined(separator: ", ")
        return (name, note)
    }
}
