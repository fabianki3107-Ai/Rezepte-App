import Foundation

/// Plattformneutrale Referenz auf einen Social-Media-Beitrag (Instagram oder TikTok).
struct SocialPostReference: Hashable {
    enum Platform: String, Hashable {
        case instagram, tiktok

        var title: String {
            switch self {
            case .instagram: return "Instagram"
            case .tiktok: return "TikTok"
            }
        }

        var host: String {
            switch self {
            case .instagram: return "instagram.com"
            case .tiktok: return "tiktok.com"
            }
        }
    }

    let platform: Platform
    /// Shortcode (Instagram) bzw. Video-ID oder Kurzlink-Code (TikTok).
    let id: String
    let username: String?
    /// Bereinigte URL ohne Tracking-Parameter.
    let canonicalURL: URL

    init(instagram reference: InstagramPostReference) {
        platform = .instagram
        id = reference.shortcode
        username = reference.username
        canonicalURL = reference.canonicalURL
    }

    init(platform: Platform, id: String, username: String?, canonicalURL: URL) {
        self.platform = platform
        self.id = id
        self.username = username
        self.canonicalURL = canonicalURL
    }
}

/// Validiert und zerlegt TikTok-Links. Kein Netzwerkzugriff.
enum TikTokLinkParser {
    private static let hosts: Set<String> = ["tiktok.com", "www.tiktok.com", "m.tiktok.com", "vm.tiktok.com", "vt.tiktok.com"]

    static func isTikTokURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    static func parse(_ url: URL) -> SocialPostReference? {
        guard isTikTokURL(url), let host = url.host?.lowercased() else { return nil }
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // https://www.tiktok.com/@user/video/7234567890123456789
        if let videoIndex = components.firstIndex(of: "video"), videoIndex + 1 < components.count {
            let videoID = components[videoIndex + 1].replacingOccurrences(of: ".html", with: "")
            guard videoID.matches(#"^\d{6,25}$"#, options: []) else { return nil }
            let username = videoIndex > 0 && components[videoIndex - 1].hasPrefix("@")
                ? String(components[videoIndex - 1].dropFirst())
                : nil
            let canonical: URL
            if let username {
                canonical = URL(string: "https://www.tiktok.com/@\(username)/video/\(videoID)")!
            } else {
                canonical = URL(string: "https://www.tiktok.com/video/\(videoID)")!
            }
            return SocialPostReference(platform: .tiktok, id: videoID, username: username, canonicalURL: canonical)
        }

        // https://m.tiktok.com/v/7234567890123456789.html
        if components.count == 2, components[0] == "v" {
            let videoID = components[1].replacingOccurrences(of: ".html", with: "")
            guard videoID.matches(#"^\d{6,25}$"#, options: []) else { return nil }
            return SocialPostReference(platform: .tiktok, id: videoID, username: nil, canonicalURL: URL(string: "https://www.tiktok.com/video/\(videoID)")!)
        }

        // Kurzlinks: https://vm.tiktok.com/ZMabc123/ und https://www.tiktok.com/t/ZTabc123/
        let code: String?
        if host.hasPrefix("vm.") || host.hasPrefix("vt."), components.count == 1 {
            code = components[0]
        } else if components.count == 2, components[0] == "t" {
            code = components[1]
        } else {
            code = nil
        }
        guard let code, code.matches(#"^[A-Za-z0-9_-]{4,20}$"#, options: []) else { return nil }
        var canonicalComponents = URLComponents()
        canonicalComponents.scheme = "https"
        canonicalComponents.host = host
        canonicalComponents.path = "/" + components.joined(separator: "/") + "/"
        guard let canonical = canonicalComponents.url else { return nil }
        return SocialPostReference(platform: .tiktok, id: code, username: nil, canonicalURL: canonical)
    }
}

/// Einstieg für alle unterstützten Plattform-Links.
enum SocialLinkParser {
    private static let urlPattern = #"https?://(?:www\.|m\.|vm\.|vt\.)?(?:instagram\.com|instagr\.am|tiktok\.com)/[^\s)\]"']+"#

    static func parse(_ url: URL) -> SocialPostReference? {
        if let instagram = InstagramLinkParser.parse(url) {
            return SocialPostReference(instagram: instagram)
        }
        return TikTokLinkParser.parse(url)
    }

    /// Findet den ersten unterstützten Link in freiem Text (z. B. geteilte Nachricht).
    static func parse(text: String) -> SocialPostReference? {
        for match in text.allMatches(of: urlPattern, options: []) {
            if let raw = match[0], let url = URL(string: raw), let reference = parse(url) {
                return reference
            }
        }
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parse(url)
        }
        return nil
    }

    static func isSupportedURL(_ url: URL) -> Bool {
        InstagramLinkParser.isInstagramURL(url) || TikTokLinkParser.isTikTokURL(url)
    }
}
