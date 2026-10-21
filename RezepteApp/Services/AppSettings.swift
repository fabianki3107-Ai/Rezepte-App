import Foundation
import Observation

/// Nutzer-Einstellungen, in `UserDefaults` gespeichert (lokal, nicht iCloud-synchronisiert).
///
/// Die Properties lesen/schreiben direkt in `UserDefaults` und melden Änderungen über
/// `access(keyPath:)` / `withMutation(keyPath:)` an das Observation-System – das ist das
/// dokumentierte Muster für `@Observable`-Typen mit eigener Speicherung.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let loadInstagramPreview = "settings.loadInstagramPreview"
        static let keepScreenAwake = "settings.keepScreenAwake"
        static let timerNotifications = "settings.timerNotifications"
        static let hapticsEnabled = "settings.hapticsEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.loadInstagramPreview: true,
            Key.keepScreenAwake: true,
            Key.timerNotifications: true,
            Key.hapticsEnabled: true
        ])
    }

    /// Beitragstext direkt von instagram.com laden (einzige Netzwerkfunktion der App).
    var loadInstagramPreview: Bool {
        get { read(\.loadInstagramPreview, Key.loadInstagramPreview) }
        set { write(\.loadInstagramPreview, Key.loadInstagramPreview, newValue) }
    }

    /// Bildschirm im Koch-Modus nicht abdunkeln.
    var keepScreenAwake: Bool {
        get { read(\.keepScreenAwake, Key.keepScreenAwake) }
        set { write(\.keepScreenAwake, Key.keepScreenAwake, newValue) }
    }

    /// Lokale Mitteilung, wenn ein Timer abläuft.
    var timerNotifications: Bool {
        get { read(\.timerNotifications, Key.timerNotifications) }
        set { write(\.timerNotifications, Key.timerNotifications, newValue) }
    }

    var hapticsEnabled: Bool {
        get { read(\.hapticsEnabled, Key.hapticsEnabled) }
        set { write(\.hapticsEnabled, Key.hapticsEnabled, newValue) }
    }

    private func read(_ keyPath: KeyPath<AppSettings, Bool>, _ key: String) -> Bool {
        access(keyPath: keyPath)
        return defaults.bool(forKey: key)
    }

    private func write(_ keyPath: KeyPath<AppSettings, Bool>, _ key: String, _ value: Bool) {
        withMutation(keyPath: keyPath) {
            defaults.set(value, forKey: key)
        }
    }
}
