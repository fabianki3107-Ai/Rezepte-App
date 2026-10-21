import UIKit
import UniformTypeIdentifiers

/// Share-Extension: nimmt Instagram-Links, Text oder Bilder aus dem System-Share-Sheet an
/// und legt sie in den App-Group-Eingang. Die App verarbeitet sie beim nächsten Öffnen.
///
/// Es findet keine Netzwerkkommunikation statt; die Extension schreibt nur lokale Dateien.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let iconView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        Task { await handleShare() }
    }

    private func configureUI() {
        view.backgroundColor = .systemGroupedBackground

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = UIImage(systemName: "square.and.arrow.down")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)

        statusLabel.text = "Wird gesichert …"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [iconView, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(card)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])
    }

    private func handleShare() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        do {
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }),
               let url = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                let text = try? await loadText(from: providers)
                try ImportInbox.enqueue(ImportInboxItem(kind: .url, url: url, text: text))
                finish(success: true, message: SocialLinkParser.isSupportedURL(url) ? "Rezept-Link gesichert" : "Link gesichert")
                return
            }
            if let text = try await loadText(from: providers) {
                let kind: ImportInboxItem.Kind = SocialLinkParser.parse(text: text) != nil ? .url : .text
                let url = SocialLinkParser.parse(text: text)?.canonicalURL
                try ImportInbox.enqueue(ImportInboxItem(kind: kind, url: url, text: text))
                finish(success: true, message: "Text gesichert")
                return
            }
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
               let data = try await loadImageData(from: provider) {
                try ImportInbox.enqueue(ImportInboxItem(kind: .image), imageData: data)
                finish(success: true, message: "Screenshot gesichert")
                return
            }
            finish(success: false, message: "Dieser Inhalt wird nicht unterstützt.")
        } catch {
            finish(success: false, message: "Sichern fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func loadText(from providers: [NSItemProvider]) async throws -> String? {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) else { return nil }
        let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        if let text = item as? String { return text }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data? {
        let item = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        if let data = item as? Data { return data }
        if let url = item as? URL { return try Data(contentsOf: url) }
        if let image = item as? UIImage { return image.jpegData(compressionQuality: 0.9) }
        return nil
    }

    private func finish(success: Bool, message: String) {
        statusLabel.text = success ? "\(message)\nÖffne „Portio“, um den Import zu prüfen." : message
        iconView.image = UIImage(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        iconView.tintColor = success ? .systemMint : .systemOrange
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if success {
                self?.extensionContext?.completeRequest(returningItems: nil)
            } else {
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "io.github.fabianki3107.portio.share", code: 1))
            }
        }
    }
}
