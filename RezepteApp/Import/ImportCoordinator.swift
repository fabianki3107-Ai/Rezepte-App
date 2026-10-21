import Foundation
import Observation
import SwiftData
import UIKit

extension SocialPostReference {
    /// Herkunft für das Rezept – im App-Target definiert, weil die Share-Extension `ImportSource` nicht kennt.
    var source: ImportSource {
        switch platform {
        case .instagram: return .instagram(canonicalURL)
        case .tiktok: return .tiktok(canonicalURL)
        }
    }
}

/// Orchestriert alle Import-Wege (Foto/Screenshot → OCR, Instagram-/TikTok-Link, Text, Share-Extension)
/// und hält den aktuellen Import-Zustand für die UI.
@MainActor
@Observable
final class ImportCoordinator {
    enum Phase: Equatable {
        case idle
        case working(String)
        case review(ParsedRecipeDraft)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .working, .review: return true
            case .idle, .failed: return false
            }
        }
    }

    private(set) var phase: Phase = .idle
    var linkInput = ""

    let repository: RecipeRepository
    private let ocr: VisionOCRManager
    private let captionFetcher: SocialCaptionFetcher
    private let settings: AppSettings

    init(
        repository: RecipeRepository,
        ocr: VisionOCRManager = .shared,
        captionFetcher: SocialCaptionFetcher = .shared,
        settings: AppSettings = .shared
    ) {
        self.repository = repository
        self.ocr = ocr
        self.captionFetcher = captionFetcher
        self.settings = settings
    }

    // MARK: - Import-Wege

    /// Screenshot oder Foto → Vision OCR → Parser → Review.
    func importImage(_ image: UIImage, source: ImportSource) async {
        phase = .working("Text wird erkannt …")
        do {
            let result = try await ocr.recognizeText(in: image)
            let heroData = ImageProcessing.heroData(from: image)
            let draft = RecipeTextParser.parse(
                result.text,
                source: source,
                ocrConfidence: result.averageConfidence,
                heroImageData: heroData
            )
            phase = .review(draft)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Freier Text (Zwischenablage, Caption) → Parser → Review.
    func importText(_ text: String, source: ImportSource, author: String? = nil, heroImageData: Data? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed("Der Text ist leer.")
            return
        }
        var draft = RecipeTextParser.parse(trimmed, source: source, sourceAuthor: author, heroImageData: heroImageData)
        if draft.sourceAuthor == nil { draft.sourceAuthor = author }
        phase = .review(draft)
    }

    /// Instagram-/TikTok-Link → Caption direkt von der Plattform (optional) → Parser → Review.
    /// Ohne Netz oder bei Login-Wall: Review mit leerem Entwurf plus Hinweis, Link bleibt als Quelle erhalten.
    func importSocialLink(_ raw: String) async {
        guard let reference = SocialLinkParser.parse(text: raw) else {
            phase = .failed("Das ist kein gültiger Instagram- oder TikTok-Link. Unterstützt werden Beiträge, Reels und Videos.")
            return
        }
        let source = reference.source

        guard settings.loadSocialPreview else {
            phase = .review(Self.linkOnlyDraft(source: source, author: reference.username))
            return
        }

        phase = .working("\(reference.platform.title)-Beitrag wird geladen …")
        do {
            let metadata = try await captionFetcher.fetchMetadata(for: reference)
            var heroData: Data?
            if let imageURL = metadata.imageURL, let data = await captionFetcher.fetchImageData(from: imageURL),
               let image = UIImage(data: data) {
                heroData = ImageProcessing.heroData(from: image)
            }
            let author = metadata.author ?? reference.username.map { "@" + $0 }
            let draft = RecipeTextParser.parse(metadata.caption ?? "", source: source, sourceAuthor: author, heroImageData: heroData)
            phase = .review(draft)
        } catch {
            var draft = Self.linkOnlyDraft(source: source, author: reference.username)
            draft.warnings.insert(.captionUnavailable, at: 0)
            phase = .review(draft)
        }
    }

    func startManualEntry() {
        phase = .review(.empty(source: .manual))
    }

    // MARK: - Externe Einstiege

    /// `rezepte://import?url=…` oder `rezepte://import?text=…` sowie direkte Instagram-/TikTok-URLs.
    func handle(incomingURL url: URL) {
        if SocialLinkParser.isSupportedURL(url) {
            Task { await importSocialLink(url.absoluteString) }
            return
        }
        guard url.scheme == "rezepte", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        if let link = items.first(where: { $0.name == "url" })?.value, !link.isEmpty {
            Task { await importSocialLink(link) }
        } else if let text = items.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            importText(text, source: ImportSource(kind: .shared, url: nil))
        }
    }

    func handle(inboxItem drained: ImportInboxService.DrainedItem) async {
        let item = drained.item
        switch item.kind {
        case .url:
            if let url = item.url {
                if SocialLinkParser.isSupportedURL(url) {
                    await importSocialLink(url.absoluteString)
                } else if let text = item.text {
                    importText(text, source: ImportSource(kind: .shared, url: url))
                }
            }
        case .text:
            if let text = item.text {
                if SocialLinkParser.parse(text: text) != nil, text.wordCount <= 3 {
                    await importSocialLink(text)
                } else {
                    importText(text, source: ImportSource(kind: .shared, url: item.url))
                }
            }
        case .image:
            if let data = drained.imageData, let image = UIImage(data: data) {
                await importImage(image, source: .screenshot)
            }
        }
    }

    // MARK: - Abschluss

    @discardableResult
    func save(_ draft: ParsedRecipeDraft) throws -> RecipeItem {
        let recipe = try repository.save(draft: draft)
        phase = .idle
        linkInput = ""
        return recipe
    }

    func reset() {
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }

    // MARK: - Hilfen

    private static func linkOnlyDraft(source: ImportSource, author: String?) -> ParsedRecipeDraft {
        var draft = ParsedRecipeDraft.empty(source: source)
        draft.sourceAuthor = author.map { "@" + $0 }
        draft.warnings = [.noIngredientsFound, .noStepsFound]
        return draft
    }

    static var preview: ImportCoordinator {
        ImportCoordinator(repository: RecipeRepository(modelContainer: RecipeSchemaV1.previewContainer()))
    }
}
