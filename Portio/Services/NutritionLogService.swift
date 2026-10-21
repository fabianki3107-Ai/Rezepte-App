import Foundation
import Observation
import SwiftData

/// Kalorien-Tagebuch: 1-Tap-Logging, Portionsänderung, Löschen und HealthKit-Abgleich.
/// Einzige Schreibstelle für `DailyLog` / `LogEntry`.
@MainActor
@Observable
final class NutritionLogService {
    struct Confirmation: Equatable, Identifiable {
        let id = UUID()
        let title: String
        let facts: NutritionFacts
        let servings: Double
    }

    /// Letzte Bestätigung für Toast-Anzeigen ("Geloggt · 450 kcal").
    private(set) var lastConfirmation: Confirmation?
    private(set) var lastHealthKitError: String?

    private let modelContainer: ModelContainer
    private let healthKit: HealthKitManager
    private let settings: AppSettings
    private let calendar: Calendar

    init(modelContainer: ModelContainer, healthKit: HealthKitManager = .shared, settings: AppSettings = .shared, calendar: Calendar = .current) {
        self.modelContainer = modelContainer
        self.healthKit = healthKit
        self.settings = settings
        self.calendar = calendar
    }

    private var context: ModelContext { modelContainer.mainContext }

    // MARK: - Lesen

    func dailyLog(for date: Date) throws -> DailyLog? {
        let day = calendar.startOfDay(for: date)
        var descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayStart == day })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Tagessummen der letzten `days` Tage (fehlende Tage als 0), ältester zuerst.
    func dailyTotals(endingAt end: Date = .now, days: Int = 7) throws -> [(day: Date, facts: NutritionFacts)] {
        let endDay = calendar.startOfDay(for: end)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else { return [] }
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate { $0.dayStart >= startDay && $0.dayStart <= endDay },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let logs = try context.fetch(descriptor)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            let facts = logs.first { calendar.isDate($0.dayStart, inSameDayAs: day) }?.totals ?? .zero
            return (day, facts)
        }
    }

    // MARK: - Schreiben

    /// 1-Tap-Log: trägt `servings` Portionen eines Rezepts zum Zeitpunkt `date` ein.
    @discardableResult
    func log(_ recipe: RecipeItem, servings: Double = 1, at date: Date = .now) throws -> LogEntry {
        let portions = max(0.25, servings)
        let dailyLog = try fetchOrCreateLog(for: date)
        let facts = recipe.nutrition.scaled(by: portions).rounded()
        let entry = LogEntry(
            loggedAt: date,
            servings: portions,
            facts: facts,
            meal: MealSlot.guess(for: date, calendar: calendar),
            recipe: recipe,
            recipeTitle: recipe.title
        )
        context.insert(entry)
        dailyLog.entries.append(entry)
        dailyLog.recalculateTotals()
        try context.save()

        lastConfirmation = Confirmation(title: recipe.title, facts: facts, servings: portions)
        syncToHealthKit(entry)
        return entry
    }

    func updateServings(_ entry: LogEntry, servings: Double) throws {
        let portions = max(0.25, servings)
        let perServing = entry.recipe?.nutrition ?? entry.facts.scaled(by: 1 / max(0.25, entry.servings))
        entry.servings = portions
        entry.facts = perServing.scaled(by: portions).rounded()
        entry.log?.recalculateTotals()
        try context.save()
        syncToHealthKit(entry)
    }

    func updateMeal(_ entry: LogEntry, meal: MealSlot) throws {
        entry.meal = meal
        try context.save()
    }

    func remove(_ entry: LogEntry) throws {
        let dailyLog = entry.log
        let syncIdentifier = entry.healthKitSyncIdentifier
        let wasSynced = entry.healthKitState == .synced
        context.delete(entry)
        dailyLog?.recalculateTotals()
        try context.save()

        if wasSynced {
            Task { [healthKit] in
                try? await healthKit.delete(syncIdentifier: syncIdentifier)
            }
        }
    }

    /// Alle noch nicht synchronisierten Einträge nach Health übertragen (z. B. nach Aktivieren der Option).
    func syncPendingEntries() throws {
        guard settings.healthKitSyncEnabled else { return }
        let pending = HealthKitSyncState.notSynced.rawValue
        let failed = HealthKitSyncState.failed.rawValue
        let disabled = HealthKitSyncState.disabled.rawValue
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.healthKitStateRaw == pending || $0.healthKitStateRaw == failed || $0.healthKitStateRaw == disabled }
        )
        for entry in try context.fetch(descriptor) {
            syncToHealthKit(entry)
        }
    }

    func clearConfirmation() {
        lastConfirmation = nil
    }

    // MARK: - Intern

    private func fetchOrCreateLog(for date: Date) throws -> DailyLog {
        if let existing = try dailyLog(for: date) { return existing }
        let log = DailyLog(day: date, calendar: calendar)
        context.insert(log)
        return log
    }

    private func syncToHealthKit(_ entry: LogEntry) {
        guard settings.healthKitSyncEnabled, healthKit.isAvailable else {
            entry.healthKitState = .disabled
            return
        }
        entry.healthKitSyncVersion += 1
        let version = entry.healthKitSyncVersion
        let facts = entry.facts
        let title = entry.displayTitle
        let date = entry.loggedAt
        let identifier = entry.healthKitSyncIdentifier

        Task { [healthKit] in
            do {
                try await healthKit.save(facts: facts, title: title, date: date, syncIdentifier: identifier, version: version)
                entry.healthKitState = .synced
                lastHealthKitError = nil
            } catch {
                entry.healthKitState = .failed
                lastHealthKitError = error.localizedDescription
            }
            try? context.save()
        }
    }
}

extension NutritionLogService {
    /// Service auf einem In-Memory-Container für Previews.
    static var preview: NutritionLogService {
        NutritionLogService(modelContainer: RecipeSchemaV1.previewContainer())
    }
}
