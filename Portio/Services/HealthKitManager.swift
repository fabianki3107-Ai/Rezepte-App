import Foundation
import HealthKit

/// Schreibt geloggte Mahlzeiten als Ernährungs-Samples in Apple Health – lokal, ohne Server.
///
/// Pro Tagebuch-Eintrag entsteht eine `HKCorrelation` vom Typ `.food` mit vier Samples
/// (Energie, Eiweiß, Kohlenhydrate, Fett). Über `HKMetadataKeySyncIdentifier` + `HKMetadataKeySyncVersion`
/// ersetzt HealthKit ältere Versionen desselben Eintrags automatisch; Löschen geht über denselben Schlüssel.
final class HealthKitManager {
    static let shared = HealthKitManager()

    enum HealthKitError: LocalizedError {
        case unavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple Health ist auf diesem Gerät nicht verfügbar."
            case .notAuthorized: return "Keine Berechtigung, Ernährungsdaten in Apple Health zu schreiben."
            }
        }
    }

    private let store = HKHealthStore()

    private let energyType = HKQuantityType(.dietaryEnergyConsumed)
    private let proteinType = HKQuantityType(.dietaryProtein)
    private let carbsType = HKQuantityType(.dietaryCarbohydrates)
    private let fatType = HKQuantityType(.dietaryFatTotal)
    private let foodType = HKCorrelationType(.food)

    private var quantityTypes: [HKQuantityType] { [energyType, proteinType, carbsType, fatType] }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Schreibberechtigung für Energie – stellvertretend für alle vier Typen.
    var isAuthorizedToWrite: Bool {
        isAvailable && store.authorizationStatus(for: energyType) == .sharingAuthorized
    }

    var authorizationStatus: HKAuthorizationStatus {
        isAvailable ? store.authorizationStatus(for: energyType) : .notDetermined
    }

    /// Fragt Schreibrechte an. Es werden keine Lesezugriffe benötigt.
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let shareTypes = Set(quantityTypes.map { $0 as HKSampleType })
        try await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    /// Speichert oder aktualisiert einen Eintrag. Gleiche `syncIdentifier` + höhere `version` ersetzt den alten Stand.
    func save(facts: NutritionFacts, title: String, date: Date, syncIdentifier: String, version: Int) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        guard isAuthorizedToWrite else { throw HealthKitError.notAuthorized }

        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: title,
            HKMetadataKeySyncIdentifier: syncIdentifier,
            HKMetadataKeySyncVersion: version
        ]

        func sample(_ type: HKQuantityType, _ value: Double, _ unit: HKUnit, suffix: String) -> HKQuantitySample {
            var sampleMetadata = metadata
            sampleMetadata[HKMetadataKeySyncIdentifier] = "\(syncIdentifier).\(suffix)"
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: max(0, value)),
                start: date,
                end: date,
                metadata: sampleMetadata
            )
        }

        let samples: Set<HKSample> = [
            sample(energyType, facts.calories, .kilocalorie(), suffix: "energy"),
            sample(proteinType, facts.protein, .gram(), suffix: "protein"),
            sample(carbsType, facts.carbs, .gram(), suffix: "carbs"),
            sample(fatType, facts.fat, .gram(), suffix: "fat")
        ]
        let correlation = HKCorrelation(type: foodType, start: date, end: date, objects: samples, metadata: metadata)
        try await store.save(correlation)
    }

    /// Entfernt alle Samples eines Eintrags (Korrelation + die vier Einzelwerte).
    func delete(syncIdentifier: String) async throws {
        guard isAvailable, isAuthorizedToWrite else { return }
        let suffixes = ["energy", "protein", "carbs", "fat"]
        for (type, suffix) in zip(quantityTypes, suffixes) {
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ["\(syncIdentifier).\(suffix)"])
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
        let correlationPredicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier])
        _ = try await store.deleteObjects(of: foodType, predicate: correlationPredicate)
    }
}
