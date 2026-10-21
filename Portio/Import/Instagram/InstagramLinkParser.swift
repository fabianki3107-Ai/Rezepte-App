import Foundation

/// Referenz auf einen Instagram-Beitrag, aus einem geteilten Link gewonnen.
struct InstagramPostReference: Hashable, Codable {
    enum Kind: String, Codable {
        case post, reel, tv

        var title: String {
            switch self {
            case .post: return "Beitrag"
            case .reel: return "Reel"
            case .tv: return "Video"
            }
        }
    }

    let shortcode: String
    let kind: Kind
    /// Nutzername, falls er Teil des Pfades war (z. B. /kochliebe/reel/ABC/).
    let username: String?

    /// Bereinigte URL ohne Tracking-Parameter (igsh, utm_*).
    var canonicalURL: URL {
        let segment: String
        switch kind {
        case .post: segment = "p"
        case .reel: segment = "reel"
        case .tv: segment = "tv"
        }
        return URL(string: "https://www.instagram.com/\(segment)/\(shortcode)/")!
    }
}

/// Validiert und zerlegt Instagram-Links. Kein Netzwerkzugriff.
enum InstagramLinkParser {
    private static let hosts: Set<String> = ["instagram.com", "www.instagram.com", "m.instagram.com", "instagr.am"]
    private static let shortcodePattern = #"^[A-Za-z0-9_-]{5,40}$"#

    static func parse(_ url: URL) -> InstagramPostReference? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // Formen: /p/CODE, /reel/CODE, /reels/CODE, /tv/CODE, /USER/p/CODE, /USER/reel/CODE
        guard let typeIndex = components.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0.lowercased()) }),
              typeIndex + 1 < components.count else { return nil }

        let shortcode = components[typeIndex + 1]
        guard shortcode.matches(shortcodePattern, options: []) else { return nil }

        let kind: InstagramPostReference.Kind
        switch components[typeIndex].lowercased() {
        case "p": kind = .post
        case "reel", "reels": kind = .reel
        default: kind = .tv
        }
        let username = typeIndex > 0 ? components[typeIndex - 1] : nil
        return InstagramPostReference(shortcode: shortcode, kind: kind, username: username)
    }

    /// Findet den ersten Instagram-Link in freiem Text (z. B. geteilte Nachricht).
    static func parse(text: String) -> InstagramPostReference? {
        let pattern = #"https?://(?:www\.|m\.)?(?:instagram\.com|instagr\.am)/[^\s)\]"']+"#
        for match in text.allMatches(of: pattern, options: []) {
            if let raw = match[0], let url = URL(string: raw), let reference = parse(url) {
                return reference
            }
        }
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parse(url)
        }
        return nil
    }

    static func isInstagramURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }
}
