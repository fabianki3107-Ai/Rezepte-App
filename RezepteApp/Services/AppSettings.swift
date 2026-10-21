import Foundation
import Observation

/// Nutzer-Einstellungen und Tagesziele, in `UserDefaults` gespeichert (lokal, nicht iCloud-synchronisiert).
///
/// Die Properties lesen/schreiben direkt in `UserDefaults` und melden Änderungen über
/// `access(keyPath:)` / `withMutation(keyPath:)` an das Observation-System.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let loadSocialPreview = "settings.loadSocialPreview"
        static let keepScreenAwake = "settings.keepScreenAwake"
        static let timerNotifications = "settings.timerNotifications"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let healthKitSyncEnabled = "settings.healthKitSyncEnabled"
        static let goalCalories = "goals.calories"
        static let goalProtein = "goals.protein"
        static let goalCarbs = "goals.carbs"
        static let goalFat = "goals.fat"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.loadSocialPreview: true,
            Key.keepScreenAwake: true,
            Key.timerNotifications: true,
            Key.hapticsEnabled: true,
            Key.healthKitSyncEnabled: false,
            Key.goalCalories: NutritionGoals.default.calories,
            Key.goalProtein: NutritionGoals.default.protein,
            Key.goalCarbs: NutritionGoals.default.carbs,
            Key.goalFat: NutritionGoals.default.fat
        ])
    }

    // MARK: Import

    /// Beitragsseite (Instagram/TikTok) direkt vom Gerät laden – einzige Netzwerkfunktion der App.
    var loadSocialPreview: Bool {
        get { readBool(\.loadSocialPreview, Key.loadSocialPreview) }
        set { writeBool(\.loadSocialPreview, Key.loadSocialPreview, newValue) }
    }

    // MARK: Koch-Modus

    var keepScreenAwake: Bool {
        get { readBool(\.keepScreenAwake, Key.keepScreenAwake) }
        set { writeBool(\.keepScreenAwake, Key.keepScreenAwake, newValue) }
    }

    var timerNotifications: Bool {
        get { readBool(\.timerNotifications, Key.timerNotifications) }
        set { writeBool(\.timerNotifications, Key.timerNotifications, newValue) }
    }

    var hapticsEnabled: Bool {
        get { readBool(\.hapticsEnabled, Key.hapticsEnabled) }
        set { writeBool(\.hapticsEnabled, Key.hapticsEnabled, newValue) }
    }

    // MARK: Tracking

    /// Geloggte Mahlzeiten zusätzlich in Apple Health schreiben.
    var healthKitSyncEnabled: Bool {
        get { readBool(\.healthKitSyncEnabled, Key.healthKitSyncEnabled) }
        set { writeBool(\.healthKitSyncEnabled, Key.healthKitSyncEnabled, newValue) }
    }

    var goals: NutritionGoals {
        get {
            access(keyPath: \.goals)
            return NutritionGoals(
                calories: defaults.integer(forKey: Key.goalCalories),
                protein: defaults.integer(forKey: Key.goalProtein),
                carbs: defaults.integer(forKey: Key.goalCarbs),
                fat: defaults.integer(forKey: Key.goalFat)
            )
        }
        set {
            withMutation(keyPath: \.goals) {
                defaults.set(max(800, newValue.calories), forKey: Key.goalCalories)
                defaults.set(max(10, newValue.protein), forKey: Key.goalProtein)
                defaults.set(max(10, newValue.carbs), forKey: Key.goalCarbs)
                defaults.set(max(10, newValue.fat), forKey: Key.goalFat)
            }
        }
    }

    // MARK: Intern

    private func readBool(_ keyPath: KeyPath<AppSettings, Bool>, _ key: String) -> Bool {
        access(keyPath: keyPath)
        return defaults.bool(forKey: key)
    }

    private func writeBool(_ keyPath: KeyPath<AppSettings, Bool>, _ key: String, _ value: Bool) {
        withMutation(keyPath: keyPath) {
            defaults.set(value, forKey: key)
        }
    }
}
