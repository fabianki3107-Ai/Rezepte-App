import Foundation
import Testing
@testable import Kochlog

@Suite("InstagramLinkParser")
struct InstagramLinkParserTests {
    @Test("Beitrag, Reel und IGTV werden erkannt")
    func kinds() throws {
        let post = try #require(InstagramLinkParser.parse(URL(string: "https://www.instagram.com/p/C1a2B3c4D5e/?igsh=abc")!))
        #expect(post.kind == .post)
        #expect(post.shortcode == "C1a2B3c4D5e")
        #expect(post.canonicalURL.absoluteString == "https://www.instagram.com/p/C1a2B3c4D5e/")

        let reel = try #require(InstagramLinkParser.parse(URL(string: "https://instagram.com/reel/XyZ_-123/")!))
        #expect(reel.kind == .reel)
        #expect(reel.canonicalURL.absoluteString == "https://www.instagram.com/reel/XyZ_-123/")

        let reels = try #require(InstagramLinkParser.parse(URL(string: "https://www.instagram.com/reels/XyZ_-123")!))
        #expect(reels.kind == .reel)

        let tv = try #require(InstagramLinkParser.parse(URL(string: "https://www.instagram.com/tv/AbCdEf/")!))
        #expect(tv.kind == .tv)
    }

    @Test("Nutzername aus Pfad")
    func username() throws {
        let reference = try #require(InstagramLinkParser.parse(URL(string: "https://www.instagram.com/kochliebe/reel/AbCdEfG/")!))
        #expect(reference.username == "kochliebe")
        #expect(reference.shortcode == "AbCdEfG")
    }

    @Test("Fremde Hosts und Profile werden abgelehnt")
    func rejects() {
        #expect(InstagramLinkParser.parse(URL(string: "https://example.com/p/abc123/")!) == nil)
        #expect(InstagramLinkParser.parse(URL(string: "https://www.instagram.com/kochliebe/")!) == nil)
        #expect(InstagramLinkParser.parse(URL(string: "https://www.instagram.com/p/")!) == nil)
    }

    @Test("Link in geteiltem Text")
    func inText() throws {
        let reference = try #require(InstagramLinkParser.parse(text: "Schau dir das an: https://www.instagram.com/p/C1a2B3c4D5e/?utm_source=ig 🍝"))
        #expect(reference.shortcode == "C1a2B3c4D5e")
    }
}

@Suite("OpenGraphParser")
struct OpenGraphParserTests {
    let html = """
    <html><head>
    <meta property="og:title" content="Kochliebe on Instagram: &quot;Cremige Tomatenpasta 🍝&#10;250 g Spaghetti&quot;" />
    <meta content="1,234 likes, 56 comments - kochliebe on March 3, 2024: &quot;Cremige Tomatenpasta 🍝&#10;250 g Spaghetti&#10;Zubereitung: Alles mischen.&quot;" property="og:description" />
    <meta property="og:image" content="https://scontent.cdninstagram.com/v/t51/abc.jpg?x=1&amp;y=2" />
    </head></html>
    """

    @Test("Caption, Autor und Bild aus Open-Graph-Tags")
    func metadata() {
        let metadata = OpenGraphParser.instagramMetadata(fromHTML: html)
        #expect(metadata.caption == "Cremige Tomatenpasta 🍝\n250 g Spaghetti\nZubereitung: Alles mischen.")
        #expect(metadata.author == "Kochliebe")
        #expect(metadata.imageURL?.absoluteString == "https://scontent.cdninstagram.com/v/t51/abc.jpg?x=1&y=2")
    }

    @Test("HTML-Entities werden dekodiert")
    func entities() {
        #expect(OpenGraphParser.decodeHTMLEntities("Salz &amp; Pfeffer &#x27;fein&#x27; &#8211; &quot;ok&quot;") == "Salz & Pfeffer 'fein' – \"ok\"")
    }

    @Test("Ohne Caption bleibt hasCaption false")
    func empty() {
        let metadata = OpenGraphParser.instagramMetadata(fromHTML: "<html><head><title>Instagram</title></head></html>")
        #expect(!metadata.hasCaption)
    }
}
