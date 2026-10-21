import SwiftUI

/// Design-Tokens nach Apple Human Interface Guidelines.
///
/// - Hintergrund: `systemGroupedBackground` (hell-grau, passt sich Dark Mode automatisch an)
/// - Interaktion: `systemBlue`
/// - Vertrauen / Erfolg: `systemMint`
///
/// Es werden ausschließlich semantische Systemfarben verwendet, damit Dark Mode,
/// erhöhter Kontrast und "Transparenz reduzieren" ohne Zusatzaufwand funktionieren.
enum AppTheme {
    // MARK: Farben
    static let background = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let tertiaryBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let accent = Color(uiColor: .systemBlue)
    static let trust = Color(uiColor: .systemMint)
    static let warning = Color(uiColor: .systemOrange)
    static let destructive = Color(uiColor: .systemRed)
    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let separator = Color(uiColor: .separator)

    // MARK: Maße (8pt-Raster)
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
        static let badge: CGFloat = 8
        static let control: CGFloat = 12
    }

    /// Mindestgröße für Touch-Ziele laut HIG.
    static let minimumTapTarget: CGFloat = 44
}

/// Karten-Container im Stil der System-"Inset Grouped"-Listen.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}
