import Foundation
import Testing
@testable import RezepteApp

@Suite("TikTokLinkParser & SocialLinkParser")
struct SocialLinkParserTests {
    @Test("TikTok-Video mit Nutzername")
    func fullVideoURL() throws {
        let reference = try #require(SocialLinkParser.parse(URL(string: "https://www.tiktok.com/@kochliebe/video/7234567890123456789?is_from_webapp=1&sender_device=pc")!))
        #expect(reference.platform == .tiktok)
        #expect(reference.id == "7234567890123456789")
        #expect(reference.username == "kochliebe")
        #expect(reference.canonicalURL.absoluteString == "https://www.tiktok.com/@kochliebe/video/7234567890123456789")
    }

    @Test("TikTok-Kurzlinks")
    func shortLinks() throws {
        let vm = try #require(TikTokLinkParser.parse(URL(string: "https://vm.tiktok.com/ZMabc1234/")!))
        #expect(vm.id == "ZMabc1234")
        #expect(vm.canonicalURL.absoluteString == "https://vm.tiktok.com/ZMabc1234/")

        let t = try #require(TikTokLinkParser.parse(URL(string: "https://www.tiktok.com/t/ZTabc1234/?k=1")!))
        #expect(t.id == "ZTabc1234")
        #expect(t.canonicalURL.absoluteString == "https://www.tiktok.com/t/ZTabc1234/")
    }

    @Test("Ungültige TikTok-Pfade")
    func rejects() {
        #expect(TikTokLinkParser.parse(URL(string: "https://www.tiktok.com/@kochliebe")!) == nil)
        #expect(TikTokLinkParser.parse(URL(string: "https://www.tiktok.com/@kochliebe/video/abc")!) == nil)
        #expect(TikTokLinkParser.parse(URL(string: "https://example.com/t/ZTabc1234/")!) == nil)
    }

    @Test("Instagram über den gemeinsamen Einstieg")
    func instagramViaSocial() throws {
        let reference = try #require(SocialLinkParser.parse(text: "Schau mal https://www.instagram.com/reel/C1a2B3c4D5e/?igsh=x"))
        #expect(reference.platform == .instagram)
        #expect(reference.id == "C1a2B3c4D5e")
        #expect(reference.canonicalURL.absoluteString == "https://www.instagram.com/reel/C1a2B3c4D5e/")
    }

    @Test("Link in Text für TikTok und Host-Erkennung")
    func inText() throws {
        let reference = try #require(SocialLinkParser.parse(text: "Rezept hier 👉 https://vt.tiktok.com/ZSabcd12/ 🍝"))
        #expect(reference.platform == .tiktok)
        #expect(SocialLinkParser.isSupportedURL(URL(string: "https://m.tiktok.com/v/123456789.html")!))
        #expect(!SocialLinkParser.isSupportedURL(URL(string: "https://youtube.com/watch?v=1")!))
    }
}

@Suite("OpenGraphParser · TikTok")
struct TikTokOpenGraphTests {
    @Test("Caption und Autor aus TikTok-Beschreibung")
    func metadata() {
        let html = """
        <html><head>
        <meta property="og:title" content="Kochliebe on TikTok" />
        <meta property="og:description" content="1234 Likes, 56 Comments. TikTok video from Kochliebe (@kochliebe): &quot;High Protein Pasta 🍝&#10;250 g Nudeln&#10;200 g Skyr&quot;" />
        <meta property="og:image" content="https://p16-sign.tiktokcdn.com/cover.jpeg?x=1" />
        </head></html>
        """
        let metadata = OpenGraphParser.tiktokMetadata(fromHTML: html)
        #expect(metadata.caption == "High Protein Pasta 🍝\n250 g Nudeln\n200 g Skyr")
        #expect(metadata.author == "@kochliebe")
        #expect(metadata.imageURL?.host == "p16-sign.tiktokcdn.com")
    }

    @Test("Beschreibung ohne Anführungszeichen ist die Caption")
    func plainDescription() {
        let html = #"<meta property="og:description" content="Schnelle Ofenkartoffeln 🥔 1 kg Kartoffeln, 3 EL Öl" />"#
        let metadata = OpenGraphParser.tiktokMetadata(fromHTML: html)
        #expect(metadata.caption == "Schnelle Ofenkartoffeln 🥔 1 kg Kartoffeln, 3 EL Öl")
    }
}
