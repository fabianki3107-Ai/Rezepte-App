import SwiftUI

/// Vertrauens-Badge in Mint: zeigt, dass ein Rezept geprüft/gekocht wurde oder die OCR zuverlässig war.
/// Unsichere Imports erhalten eine orangefarbene Variante, damit der Nutzer gezielt nachprüft.
struct TrustBadgeView: View {
    enum Style {
        case trusted(String, systemImage: String)
        case review(String, systemImage: String)
        case neutral(String, systemImage: String)
    }

    let style: Style
    var compact = false

    init(recipe: Recipe, compact: Bool = false) {
        self.compact = compact
        self.style = Self.style(for: recipe)
    }

    init(style: Style, compact: Bool = false) {
        self.style = style
        self.compact = compact
    }

    var body: some View {
        Label {
            if !compact { Text(title) }
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? AppTheme.Spacing.xs + 2 : AppTheme.Spacing.s)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityLabel(title)
    }

    private var title: String {
        switch style {
        case .trusted(let text, _), .review(let text, _), .neutral(let text, _): return text
        }
    }

    private var systemImage: String {
        switch style {
        case .trusted(_, let image), .review(_, let image), .neutral(_, let image): return image
        }
    }

    private var tint: Color {
        switch style {
        case .trusted: return AppTheme.trust
        case .review: return AppTheme.warning
        case .neutral: return AppTheme.secondaryLabel
        }
    }

    static func style(for recipe: Recipe) -> Style {
        switch recipe.verification {
        case .cooked:
            return .trusted("Gekocht", systemImage: "checkmark.seal.fill")
        case .userVerified:
            return .trusted("Geprüft", systemImage: "checkmark.seal.fill")
        case .unverified:
            if let confidence = recipe.ocrConfidence {
                return confidence >= 0.85
                    ? .trusted("Gut erkannt", systemImage: "text.viewfinder")
                    : .review("Bitte prüfen", systemImage: "exclamationmark.triangle.fill")
            }
            return .neutral("Ungeprüft", systemImage: "circle.dashed")
        }
    }
}

/// Fester Hinweis "Offline gespeichert" – nutzt dieselbe Optik.
struct OfflineBadgeView: View {
    var body: some View {
        TrustBadgeView(style: .trusted("Nur auf diesem Gerät", systemImage: "lock.iphone"))
    }
}

#Preview {
    VStack(spacing: 12) {
        TrustBadgeView(recipe: Recipe.sampleShakshuka())
        TrustBadgeView(recipe: Recipe.samplePancakes())
        TrustBadgeView(recipe: Recipe(title: "Manuell"))
        OfflineBadgeView()
    }
    .padding()
    .background(AppTheme.background)
}
