import Foundation
import SwiftData

/// Ein Zubereitungsschritt. Erkannte Dauer und Temperatur speisen den Koch-Modus (Timer, Hinweise).
@Model
final class CookingStep {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var text: String
    /// Aus dem Text erkannte Dauer ("10 Minuten köcheln"), Grundlage für den Schritt-Timer.
    var durationSeconds: Int?
    /// Erkannte Temperatur ("bei 180 °C backen").
    var temperatureCelsius: Int?
    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        sortIndex: Int,
        text: String,
        durationSeconds: Int? = nil,
        temperatureCelsius: Int? = nil
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.text = text
        self.durationSeconds = durationSeconds
        self.temperatureCelsius = temperatureCelsius
    }

    var hasTimer: Bool { (durationSeconds ?? 0) > 0 }
}
