import Foundation

/// Metadaten eines Instagram-Beitrags aus dessen Open-Graph-Tags.
struct InstagramPostMetadata: Hashable {
    var caption: String?
    var author: String?
    var imageURL: URL?

    var hasCaption: Bool { !(caption ?? "").isEmpty }
}

enum InstagramFetchError: LocalizedError {
    case offline
    case blocked
    case noCaption

    var errorDescription: String? {
        switch self {
        case .offline: return "Keine Internetverbindung. Du kannst den Beitragstext auch einfügen oder einen Screenshot importieren."
        case .blocked: return "Instagram hat die Vorschau nicht herausgegeben. Importiere stattdessen einen Screenshot."
        case .noCaption: return "Der Beitrag enthält keinen lesbaren Text."
        }
    }
}

/// Lädt die öffentliche Beitragsseite **direkt vom Gerät** und liest die Open-Graph-Metadaten.
///
/// Es gibt keinen Zwischenserver: Die Anfrage geht an instagram.com, so wie beim Öffnen im Browser.
/// Die Session ist `ephemeral` (keine Cookies, kein Cache). Schlägt der Abruf fehl – etwa wegen
/// Login-Wall – fällt die App auf Screenshot-OCR oder manuelles Einfügen zurück.
actor InstagramCaptionFetcher {
    static let shared = InstagramCaptionFetcher()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.waitsForConnectivity = false
            configuration.httpAdditionalHeaders = [
                "Accept": "text/html",
                "Accept-Language": "de-DE,de;q=0.9,en;q=0.7"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchMetadata(for reference: InstagramPostReference) async throws -> InstagramPostMetadata {
        var request = URLRequest(url: reference.canonicalURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw InstagramFetchError.offline
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw InstagramFetchError.blocked
        }

        let metadata = OpenGraphParser.instagramMetadata(fromHTML: html)
        guard metadata.hasCaption else { throw InstagramFetchError.noCaption }
        return metadata
    }

    func fetchImageData(from url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 15_000_000 else { return nil }
        return data
    }
}

/// Minimaler Open-Graph-Parser (Regex, kein HTML-DOM nötig). Testbar ohne Netzwerk.
enum OpenGraphParser {
    static func properties(fromHTML html: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"<meta\s+(?:[^>]*?\s)?(?:property|name)=["'](og:[a-z:_]+|description)["'][^>]*?content=["']([^"']*)["'][^>]*>"#
        let reversed = #"<meta\s+(?:[^>]*?\s)?content=["']([^"']*)["'][^>]*?(?:property|name)=["'](og:[a-z:_]+|description)["'][^>]*>"#
        for match in html.allMatches(of: pattern) {
            if let key = match[1], let value = match[2], result[key] == nil { result[key] = decodeHTMLEntities(value) }
        }
        for match in html.allMatches(of: reversed) {
            if let key = match[2], let value = match[1], result[key] == nil { result[key] = decodeHTMLEntities(value) }
        }
        return result
    }

    /// Instagram liefert z. B.
    /// og:title: `Name on Instagram: "Caption…"`
    /// og:description: `1,234 likes, 56 comments - name on March 3, 2024: "Caption…"`
    static func instagramMetadata(fromHTML html: String) -> InstagramPostMetadata {
        let og = properties(fromHTML: html)
        let description = og["og:description"] ?? og["description"] ?? ""
        let title = og["og:title"] ?? ""

        var caption = extractQuotedCaption(from: description) ?? extractQuotedCaption(from: title)
        if caption == nil, !description.isEmpty, !description.matches(#"^\d[\d.,]*\s*(likes|gefällt)"#) {
            caption = description
        }

        var author: String?
        if let match = title.firstMatch(of: #"^(.+?)\s+(?:on|auf)\s+instagram"#), let name = match[1] {
            author = name.trimmingCharacters(in: .whitespaces)
        } else if let match = description.firstMatch(of: #"-\s*([\w.]{2,30})\s+(?:on|am)\s"#), let handle = match[1] {
            author = "@" + handle
        }

        return InstagramPostMetadata(
            caption: caption?.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author,
            imageURL: og["og:image"].flatMap { URL(string: $0) }
        )
    }

    private static func extractQuotedCaption(from text: String) -> String? {
        guard let range = text.range(of: #":\s*["“]"#, options: .regularExpression) else { return nil }
        var caption = String(text[range.upperBound...])
        if let last = caption.lastIndex(where: { $0 == "\"" || $0 == "”" }) {
            caption = String(caption[..<last])
        }
        return caption.isEmpty ? nil : caption
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let named: [String: String] = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#10;": "\n", "&#xa;": "\n", "&#x0A;": "\n"
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        // Numerische Entities &#NNNN; / &#xHHHH;
        for match in result.allMatches(of: #"&#(x?)([0-9a-fA-F]+);"#) {
            guard let whole = match[0], let digits = match[2] else { continue }
            let isHex = !(match[1] ?? "").isEmpty
            if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                result = result.replacingOccurrences(of: whole, with: String(Character(scalar)))
            }
        }
        return result
    }
}
