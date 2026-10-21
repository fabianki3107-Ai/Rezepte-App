import Foundation

/// Heuristischer Parser, der freien Rezepttext (OCR-Ausgabe, Instagram-Caption, Zwischenablage)
/// in einen strukturierten `ParsedRecipeDraft` überführt.
///
/// Strategie:
/// 1. Zeilen normalisieren und Rauschen entfernen (Hashtags, UI-Reste, "Folge mir").
/// 2. Abschnitte über Überschriften ("Zutaten", "Zubereitung") erkennen – fehlen sie,
///    werden Zeilen über ihre Form klassifiziert (Mengenangabe vs. Fließtext).
/// 3. Titel, Portionen, Zeiten, Tags aus dem Vorspann ziehen.
/// 4. Zutaten mit `IngredientLineParser`, Schritte mit `StepAnnotator` anreichern.
enum RecipeTextParser {
    private enum Section { case preamble, ingredients, steps, notes }

    private struct Line {
        let text: String
        let section: Section
    }

    private static let ingredientsHeader = #"^(zutaten|ingredients|einkaufsliste|du brauchst|ihr braucht|das brauchst du|was du brauchst|you need|you'll need|benötigt)\b"#
    private static let stepsHeader = #"^(zubereitung|anleitung|so geht'?s|so wird'?s gemacht|schritte|zubereitungsschritte|instructions|directions|method|steps|preparation|how to|und so geht'?s|los geht'?s)\b"#
    private static let notesHeader = #"^(tipp|tipps|tip|tips|hinweis|hinweise|notizen|notes|nährwerte|nutrition|lagerung|storage|serviervorschlag)\b"#
    private static let noisePattern = #"(folg(e|t) (mir|uns)|link in (der )?bio|speicher(e|t)? (dir|euch)|mehr rezepte|^werbung|^anzeige|kommentier|markier(e|t)|gefällt \d+ mal|\d+ likes|\d+ kommentare|mehr anzeigen|weniger anzeigen|^antworten|vor \d+ (tagen|stunden|minuten|wochen)|follow (me|us)|sponsored|bezahlte partnerschaft|paid partnership|original audio|originalton|^audio|rezept speichern|save this|view all \d+ comments|alle \d+ kommentare)"#
    private static let stepNumbering = #"^(?:(?:schritt|step)[ \t]*\d{1,2}[.):]?|\d{1,2}[.):]|[-•*·▪►▶])[ \t]*"#
    private static let genericHashtags: Set<String> = [
        "rezept", "rezepte", "food", "foodporn", "instafood", "yummy", "recipe", "recipes", "kochen",
        "lecker", "foodie", "foodblogger", "essen", "homemade", "selbstgemacht", "reels", "reel", "fyp",
        "viral", "foodstagram", "delicious", "eat", "dinner", "lunch", "healthyfood", "foodlover"
    ]

    // MARK: - API

    static func parse(
        _ text: String,
        source: ImportSource = .manual,
        sourceAuthor: String? = nil,
        ocrConfidence: Double? = nil,
        heroImageData: Data? = nil
    ) -> ParsedRecipeDraft {
        let normalized = text.normalizedForParsing
        let rawLines = normalized
            .components(separatedBy: .newlines)
            .map { $0.collapsingWhitespace }
            .filter { !$0.isEmpty && !isNoise($0) }

        let lines = assignSections(rawLines)
        let preamble = lines.filter { $0.section == .preamble }.map(\.text)
        let ingredientLines = lines.filter { $0.section == .ingredients }.map(\.text)
        let stepLines = lines.filter { $0.section == .steps }.map(\.text)
        let noteLines = lines.filter { $0.section == .notes }.map(\.text)

        var warnings: [ParsedRecipeDraft.Warning] = []

        let title = extractTitle(from: preamble, fallback: rawLines)
        let summary = extractSummary(from: preamble, excludingTitle: title)
        let ingredients = parseIngredients(ingredientLines)
        let steps = parseSteps(stepLines)
        let tags = extractTags(from: normalized)
        let times = extractTimes(from: normalized)
        var servings = extractServings(from: normalized)
        let author = sourceAuthor ?? extractAuthor(from: preamble)

        if servings == nil {
            servings = 4
            warnings.append(.servingsGuessed)
        }
        if ingredients.isEmpty { warnings.append(.noIngredientsFound) }
        if steps.isEmpty { warnings.append(.noStepsFound) }
        if let ocrConfidence, ocrConfidence < 0.8 { warnings.append(.lowConfidence(ocrConfidence)) }

        return ParsedRecipeDraft(
            title: title,
            summary: summary,
            notes: noteLines.isEmpty ? nil : noteLines.joined(separator: "\n"),
            servings: servings,
            prepTimeMinutes: times.prep,
            cookTimeMinutes: times.cook,
            ingredients: ingredients,
            steps: steps,
            tags: tags,
            source: source,
            sourceAuthor: author,
            ocrConfidence: ocrConfidence,
            heroImageData: heroImageData,
            rawText: text,
            warnings: warnings
        )
    }

    // MARK: - Rauschen

    static func isNoise(_ line: String) -> Bool {
        let stripped = line.removingEmoji.collapsingWhitespace
        if stripped.isEmpty { return true }
        if stripped.rangeOfCharacter(from: .letters) == nil && stripped.rangeOfCharacter(from: CharacterSet(charactersIn: "½⅓⅔¼¾⅛")) == nil {
            return true // nur Symbole/Zahlen, z. B. Trennlinien oder Uhrzeit
        }
        if stripped.matches(#"^@[\w.]+$"#) { return true }
        if stripped.hasPrefix("#") { return true }
        if stripped.allMatches(of: #"#\p{L}[\p{L}\d_]*"#).count >= 2 { return true }
        if stripped.matches(#"^\d{1,2}:\d{2}\b"#) && stripped.wordCount <= 3 { return true }
        if stripped.lowercased().matches(noisePattern) { return true }
        return false
    }

    // MARK: - Abschnitte

    private static func headerSection(for line: String) -> Section? {
        let probe = line.removingEmoji.trimmedPunctuation.lowercased()
        guard probe.count <= 48 else { return nil }
        if probe.matches(ingredientsHeader) { return .ingredients }
        if probe.matches(stepsHeader) { return .steps }
        if probe.matches(notesHeader) { return .notes }
        return nil
    }

    private static func assignSections(_ lines: [String]) -> [Line] {
        var result: [Line] = []
        var current: Section = .preamble
        var sawIngredientsHeader = false
        var sawStepsHeader = false

        for line in lines {
            if let header = headerSection(for: line) {
                current = header
                if header == .ingredients { sawIngredientsHeader = true }
                if header == .steps { sawStepsHeader = true }
                // Überschrift wie "Zutaten für 4 Personen" trägt Info, Rest der Zeile ggf. eine Zutat
                continue
            }

            switch current {
            case .preamble where !sawIngredientsHeader:
                // Ohne Überschrift: erste Zutaten-Zeile eröffnet den Zutatenteil
                if IngredientLineParser.looksLikeIngredient(line) {
                    current = .ingredients
                    result.append(Line(text: line, section: .ingredients))
                } else if looksLikeStep(line), result.contains(where: { $0.section == .ingredients }) {
                    current = .steps
                    result.append(Line(text: line, section: .steps))
                } else {
                    result.append(Line(text: line, section: .preamble))
                }
            case .ingredients where !sawStepsHeader:
                // Zutatenblock endet, sobald Fließtext beginnt
                if looksLikeStep(line) && !IngredientLineParser.looksLikeIngredient(line) {
                    current = .steps
                    result.append(Line(text: line, section: .steps))
                } else {
                    result.append(Line(text: line, section: .ingredients))
                }
            default:
                result.append(Line(text: line, section: current))
            }
        }
        return result
    }

    /// Fließtext-Heuristik: lange Zeilen, Satzzeichen oder Nummerierung.
    static func looksLikeStep(_ line: String) -> Bool {
        if line.matches(stepNumbering) && line.wordCount >= 3 { return true }
        if line.wordCount >= 8 { return true }
        return line.wordCount >= 5 && line.hasSuffix(".")
    }

    // MARK: - Titel & Vorspann

    private static func extractTitle(from preamble: [String], fallback: [String]) -> String {
        let candidates = preamble + fallback
        for raw in candidates {
            let cleaned = raw.removingEmoji
                .replacingMatches(of: #"#\p{L}[\p{L}\d_]*"#, with: "")
                .collapsingWhitespace
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—•*·:;,."))
            guard !cleaned.isEmpty, cleaned.wordCount <= 10, cleaned.count >= 3 else { continue }
            if headerSection(for: raw) != nil || cleaned.matches(#"^@"#) { continue }
            if extractServings(from: cleaned) != nil && cleaned.wordCount <= 4 { continue }
            if cleaned.matches(#"^\d"#) { continue }
            // Reine Großschreibung lesbar machen ("SHAKSHUKA MIT FETA")
            if cleaned == cleaned.uppercased(), cleaned.rangeOfCharacter(from: .lowercaseLetters) == nil {
                return cleaned.capitalized
            }
            return cleaned.capitalizingFirstLetter
        }
        return "Importiertes Rezept"
    }

    private static func extractSummary(from preamble: [String], excludingTitle title: String) -> String? {
        let body = preamble
            .map { $0.removingEmoji.replacingMatches(of: #"#\p{L}[\p{L}\d_]*"#, with: "").collapsingWhitespace }
            .filter { line in
                !line.isEmpty
                && line.trimmedPunctuation.caseInsensitiveCompare(title) != .orderedSame
                && !line.matches(#"^@"#)
                && extractServings(from: line) == nil
                && extractTimes(from: line) == (nil, nil)
            }
        guard !body.isEmpty else { return nil }
        let joined = body.joined(separator: " ")
        return joined.count > 280 ? String(joined.prefix(277)) + "…" : joined
    }

    private static func extractAuthor(from preamble: [String]) -> String? {
        for line in preamble {
            if let match = line.firstMatch(of: #"(@[\w.]{2,30})"#), let handle = match[1] {
                return handle
            }
        }
        return nil
    }

    private static func extractTags(from text: String) -> [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for match in text.allMatches(of: #"#(\p{L}[\p{L}\d_]{1,24})"#) {
            guard let raw = match[1] else { continue }
            let key = raw.lowercased()
            guard !genericHashtags.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            tags.append(Tag.normalized(raw))
            if tags.count == 6 { break }
        }
        return tags
    }

    // MARK: - Portionen & Zeiten

    static func extractServings(from text: String) -> Int? {
        let patterns = [
            #"(\d{1,2})[ \t]*(?:-|–|bis)?[ \t]*\d{0,2}[ \t]*(?:portionen|portion|personen|person|servings|serving|pers\.)"#,
            #"(?:für|for|ergibt|reicht für|yield[s]?|makes|serves)[ \t]*(?:ca\.?|etwa|about|approx\.?)?[ \t]*(\d{1,2})(?![ \t]*(?:min|std|sek|h\b|g\b|ml|cm|°))"#,
            #"(?:portionen|servings|personen)[ \t]*[:=][ \t]*(\d{1,2})"#
        ]
        for pattern in patterns {
            if let match = text.firstMatch(of: pattern), let value = match[1].flatMap({ Int($0) }), (1...48).contains(value) {
                return value
            }
        }
        return nil
    }

    static func extractTimes(from text: String) -> (prep: Int?, cook: Int?) {
        let unit = #"(min|minuten|minute|mins|std|stunden|stunde|h|hours|hour|hrs|hr)\b"#
        let prepPattern = #"(?:zubereitungszeit|vorbereitung(?:szeit)?|arbeitszeit|prep(?:aration)?[ \t]*time|prep)[ \t]*[:\-–]?[ \t]*(?:ca\.?|etwa|about)?[ \t]*(\d{1,3}(?:[,.]\d)?)[ \t]*"# + unit
        let cookPattern = #"(?:kochzeit|koch-?/?backzeit|backzeit|garzeit|gesamtzeit|dauer|cook(?:ing)?[ \t]*time|bake[ \t]*time|total[ \t]*time)[ \t]*[:\-–]?[ \t]*(?:ca\.?|etwa|about)?[ \t]*(\d{1,3}(?:[,.]\d)?)[ \t]*"# + unit
        let iconPattern = #"[⏱⏰🕒🕑⌚][ \t]*(?:ca\.?|etwa|about)?[ \t]*(\d{1,3}(?:[,.]\d)?)[ \t]*"# + unit

        func minutes(_ match: [String?]?) -> Int? {
            guard let match, let raw = match[1], let value = Double(raw.replacingOccurrences(of: ",", with: ".")),
                  let unitText = match[2]?.lowercased() else { return nil }
            let isHours = unitText.hasPrefix("h") || unitText.hasPrefix("st")
            return Int((isHours ? value * 60 : value).rounded())
        }

        let prep = minutes(text.firstMatch(of: prepPattern))
        var cook = minutes(text.firstMatch(of: cookPattern))
        if prep == nil, cook == nil {
            cook = minutes(text.firstMatch(of: iconPattern))
        }
        return (prep, cook)
    }

    // MARK: - Zutaten

    private static func parseIngredients(_ lines: [String]) -> [DraftIngredient] {
        var result: [DraftIngredient] = []
        var currentGroup: String?

        for line in lines {
            let cleaned = line.removingEmoji.collapsingWhitespace
            if isGroupHeader(cleaned) {
                currentGroup = cleaned.trimmedPunctuation.capitalizingFirstLetter
                continue
            }
            guard let ingredient = DraftIngredient.from(line: cleaned, group: currentGroup) else { continue }
            // Fließtext, der versehentlich im Zutatenteil landet, nicht als Zutat führen
            if !ingredient.measure.quantity.isFinite(orNil: true) || ingredient.name.wordCount > 7 { continue }
            result.append(ingredient)
        }
        return result
    }

    private static func isGroupHeader(_ line: String) -> Bool {
        guard line.wordCount <= 6 else { return false }
        if line.hasSuffix(":") { return true }
        return line.matches(#"^(für|for)\s+(den|die|das|the)\b"#)
    }

    // MARK: - Schritte

    private static func parseSteps(_ lines: [String]) -> [DraftStep] {
        var buffer: [String] = []
        var current = ""

        func flush() {
            let text = current.collapsingWhitespace
            if !text.isEmpty { buffer.append(text) }
            current = ""
        }

        for raw in lines {
            let hasNumbering = raw.matches(stepNumbering)
            let line = raw.replacingMatches(of: stepNumbering, with: "").removingEmoji.collapsingWhitespace
            guard !line.isEmpty else { continue }

            let startsLowercase = line.first.map { $0.isLowercase } ?? false
            let previousOpen = current.hasSuffix(",") || current.lowercased().hasSuffix(" und") || current.lowercased().hasSuffix(" oder")
            let isContinuation = !hasNumbering && !current.isEmpty && (startsLowercase || previousOpen)

            if isContinuation {
                current += " " + line
            } else {
                flush()
                current = line
            }
        }
        flush()

        // Ein einzelner Textblock → in Sätze zerlegen, damit der Koch-Modus Schritt für Schritt führen kann
        if buffer.count == 1, let only = buffer.first,
           only.count > 160 || only.allMatches(of: #"[.!?](\s|$)"#, options: []).count >= 3 {
            buffer = only.components(separatedBy: .newlines)
                .flatMap { $0.splitIntoSentences() }
                .map { $0.collapsingWhitespace }
                .filter { !$0.isEmpty }
        }

        return buffer.map { DraftStep.from(text: $0.capitalizingFirstLetter) }
    }
}

/// Erkennt Zeitangaben und Temperaturen in einem Schritt-Text für Timer und Hinweise.
enum StepAnnotator {
    struct Annotations: Hashable {
        var durationSeconds: Int?
        var temperatureCelsius: Int?
    }

    private static let durationPattern = #"(\d+(?:[,.]\d+)?)[ \t]*(?:(?:-|–|bis|to)[ \t]*(\d+(?:[,.]\d+)?))?[ \t]*(sekunden|sekunde|sek|sec|seconds|second|secs|minuten|minute|min|mins|minutes|stunden|stunde|std|hours|hour|hrs|hr|h)\b\.?"#
    private static let wordDurationPattern = #"\b(eine|einer|halbe|halben|eineinhalb|anderthalb|zwei|drei|vier|fünf|zehn)[ \t]+(stunden|stunde|minuten|minute)\b"#
    private static let temperaturePattern = #"(\d{2,3})[ \t]*(?:°|º|grad)[ \t]*(c|celsius|f|fahrenheit)?\b"#

    static func annotate(_ text: String) -> Annotations {
        Annotations(durationSeconds: duration(in: text), temperatureCelsius: temperature(in: text))
    }

    static func duration(in text: String) -> Int? {
        if let match = text.firstMatch(of: durationPattern),
           let raw = match[1], let unitText = match[3]?.lowercased() {
            // Bei "10–15 Minuten" die Obergrenze nehmen – lieber zu lang als zu kurz
            let chosen = match[2] ?? raw
            guard let value = Double(chosen.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return Int((value * multiplier(for: unitText)).rounded())
        }
        if let match = text.lowercased().firstMatch(of: wordDurationPattern),
           let word = match[1], let unitText = match[2] {
            let values: [String: Double] = [
                "eine": 1, "einer": 1, "halbe": 0.5, "halben": 0.5, "eineinhalb": 1.5, "anderthalb": 1.5,
                "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "zehn": 10
            ]
            guard let value = values[word] else { return nil }
            return Int((value * multiplier(for: unitText)).rounded())
        }
        return nil
    }

    static func temperature(in text: String) -> Int? {
        guard let match = text.firstMatch(of: temperaturePattern),
              let raw = match[1], let value = Int(raw) else { return nil }
        let isFahrenheit = match[2]?.lowercased().hasPrefix("f") ?? false
        if isFahrenheit {
            let celsius = Double(value - 32) * 5 / 9
            return Int((celsius / 5).rounded() * 5)
        }
        return (40...300).contains(value) ? value : nil
    }

    private static func multiplier(for unit: String) -> Double {
        if unit.hasPrefix("sek") || unit.hasPrefix("sec") { return 1 }
        if unit.hasPrefix("min") { return 60 }
        return 3600 // Stunden
    }
}

private extension Optional where Wrapped == Double {
    func isFinite(orNil: Bool) -> Bool {
        switch self {
        case .none: return orNil
        case .some(let value): return value.isFinite
        }
    }
}

private extension String {
    /// Satztrennung an ". ", "! ", "? " gefolgt von Großbuchstabe oder Ziffer.
    func splitIntoSentences() -> [String] {
        guard let regex = RegexCache.regex(#"(?<=[.!?])\s+(?=[A-ZÄÖÜ\d])"#, options: []) else { return [self] }
        var sentences: [String] = []
        var lastIndex = startIndex
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let range = Range(match.range, in: self) else { continue }
            sentences.append(String(self[lastIndex..<range.lowerBound]))
            lastIndex = range.upperBound
        }
        sentences.append(String(self[lastIndex...]))
        return sentences
    }
}
