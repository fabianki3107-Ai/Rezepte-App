import Foundation

/// Kleine Regex-Hilfen auf Basis von `NSRegularExpression` (ICU, unicode-fähig).
extension String {
    /// Erste Übereinstimmung inklusive Capture-Gruppen (Index 0 = gesamter Treffer).
    func firstMatch(of pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String?]? {
        guard let regex = RegexCache.regex(pattern, options: options) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let groupRange = match.range(at: index)
            guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: self) else { return nil }
            return String(self[swiftRange])
        }
    }

    /// Alle Übereinstimmungen (jeweils mit Capture-Gruppen).
    func allMatches(of pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [[String?]] {
        guard let regex = RegexCache.regex(pattern, options: options) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let groupRange = match.range(at: index)
                guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: self) else { return nil }
                return String(self[swiftRange])
            }
        }
    }

    func matches(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> Bool {
        firstMatch(of: pattern, options: options) != nil
    }

    func replacingMatches(of pattern: String, with template: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> String {
        guard let regex = RegexCache.regex(pattern, options: options) else { return self }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }

    /// Mehrfach-Leerzeichen zusammenziehen, Ränder trimmen.
    var collapsingWhitespace: String {
        replacingMatches(of: #"\s+"#, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Entfernt Emojis und Symbol-Piktogramme (nicht aber Bruchzeichen wie ½).
    var removingEmoji: String {
        String(unicodeScalars.filter { scalar in
            if scalar.properties.isEmojiPresentation { return false }
            if scalar.properties.isEmoji && scalar.value > 0x238C { return false }
            // Variation Selector / Zero Width Joiner, die Emojis begleiten
            if scalar.value == 0xFE0F || scalar.value == 0x200D { return false }
            return true
        }.map { Character($0) })
    }

    var trimmedPunctuation: String {
        trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—•*·:;,.!?"))
    }

    var capitalizingFirstLetter: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Anzahl der Wörter (whitespace-getrennt).
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Ersetzt typografische Varianten (Bruchstrich, geschützte Leerzeichen), die OCR gerne liefert.
    var normalizedForParsing: String {
        var result = self
        let replacements: [String: String] = [
            "\u{00A0}": " ", "\u{2009}": " ", "\u{202F}": " ",
            "\u{2044}": "/", "\u{2215}": "/",
            "’": "'", "‘": "'", "`": "'",
            "“": "\"", "”": "\"",
            "\u{2010}": "-", "\u{2011}": "-", "\u{2012}": "-"
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }
}

/// Kompilierte Regexe sind teuer; sie werden einmal pro Muster gecacht.
enum RegexCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func regex(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)"
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            assertionFailure("Ungültiges Regex-Muster: \(pattern)")
            return nil
        }
        cache[key] = regex
        return regex
    }
}
