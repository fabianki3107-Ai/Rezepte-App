import SwiftUI
import SwiftData

/// Einstellungen: Datenschutz-Status, Verhalten im Koch-Modus, lokaler Export, Löschen.
struct SettingsView: View {
    @Environment(ImportCoordinator.self) private var coordinator
    @Environment(NutritionLogService.self) private var nutritionLog
    @Query private var recipes: [RecipeItem]
    @State private var settings = AppSettings.shared
    @State private var healthKitError: String?
    @State private var isRequestingHealthKit = false
    @State private var exportFile: ExportFile?
    @State private var showDeleteAll = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: AppTheme.Spacing.m) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title)
                            .foregroundStyle(AppTheme.trust)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Alles bleibt auf diesem Gerät")
                                .font(.headline)
                            Text("Keine Cloud, kein Konto, kein Tracking. Texterkennung läuft mit Apple Vision lokal.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                    LabeledContent("Gespeicherte Rezepte", value: "\(recipes.count)")
                }

                Section {
                    goalStepper("Kalorien", unit: "kcal", value: settings.goals.calories, range: 800...6000, step: 50) { settings.goals.calories = $0 }
                    goalStepper("Eiweiß", unit: "g", value: settings.goals.protein, range: 10...400, step: 5) { settings.goals.protein = $0 }
                    goalStepper("Kohlenhydrate", unit: "g", value: settings.goals.carbs, range: 10...800, step: 5) { settings.goals.carbs = $0 }
                    goalStepper("Fett", unit: "g", value: settings.goals.fat, range: 10...300, step: 5) { settings.goals.fat = $0 }
                } header: {
                    Text("Tagesziele")
                } footer: {
                    Text("Aus den Makro-Zielen ergeben sich \(settings.goals.caloriesFromMacroGoals) kcal (4/4/9-Regel).")
                }

                Section {
                    Toggle("Mahlzeiten in Apple Health schreiben", isOn: healthKitBinding)
                        .disabled(isRequestingHealthKit || !HealthKitManager.shared.isAvailable)
                    LabeledContent("Status", value: healthKitStatusText)
                    if let error = nutritionLog.lastHealthKitError {
                        Text(error).font(.footnote).foregroundStyle(AppTheme.warning)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Kalorien, Eiweiß, Kohlenhydrate und Fett werden lokal in Health eingetragen – ohne Cloud. Änderst oder löschst du einen Eintrag, wird er auch dort aktualisiert.")
                }

                Section {
                    Toggle("Beitrag direkt von Instagram/TikTok laden", isOn: $settings.loadSocialPreview)
                } header: {
                    Text("Import")
                } footer: {
                    Text("Wenn aktiv, lädt die App beim Link-Import die Beitragsseite direkt von der Plattform – wie ein Browser, ohne Zwischenserver. Deaktiviert: Link wird nur als Quelle gespeichert, Inhalte kommen per Screenshot oder Einfügen.")
                }

                Section("Koch-Modus") {
                    Toggle("Bildschirm anlassen", isOn: $settings.keepScreenAwake)
                    Toggle("Timer-Mitteilungen", isOn: $settings.timerNotifications)
                    Toggle("Haptisches Feedback", isOn: $settings.hapticsEnabled)
                }

                Section {
                    Button {
                        exportRecipes()
                    } label: {
                        Label("Als JSON exportieren", systemImage: "square.and.arrow.up")
                    }
                    .disabled(recipes.isEmpty)

                    Button(role: .destructive) {
                        showDeleteAll = true
                    } label: {
                        Label("Alle Rezepte löschen", systemImage: "trash")
                    }
                    .disabled(recipes.isEmpty)
                } header: {
                    Text("Daten")
                } footer: {
                    Text("Der Export ist eine lokale Datei, die du z. B. in „Dateien“ sichern kannst.")
                }

                Section("Über") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    LabeledContent("Texterkennung", value: "Apple Vision (on-device)")
                    LabeledContent("Nährwerte", value: "Lokale Datenbank, \(FoodDatabase.entries.count) Lebensmittel")
                    LabeledContent("Datenbank", value: "SwiftData, lokal")
                }
            }
            .navigationTitle("Einstellungen")
            .sheet(item: $exportFile) { file in
                VStack(spacing: AppTheme.Spacing.l) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent)
                    Text(file.url.lastPathComponent)
                        .font(.headline)
                    Text("\(recipes.count) Rezepte als JSON. Du entscheidest, wo die Datei landet – z. B. in „Dateien“.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    ShareLink(item: file.url, preview: SharePreview("Rezepte-Export", image: Image(systemName: "doc.text"))) {
                        Label("Datei sichern oder teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(AppTheme.Spacing.xl)
                .presentationDetents([.medium])
            }
            .confirmationDialog("Alle Rezepte löschen?", isPresented: $showDeleteAll, titleVisibility: .visible) {
                Button("\(recipes.count) Rezepte löschen", role: .destructive) {
                    try? coordinator.repository.deleteAll()
                }
            } message: {
                Text("Dieser Schritt kann nicht rückgängig gemacht werden. Erstelle vorher einen Export.")
            }
            .alert("Apple Health", isPresented: Binding(get: { healthKitError != nil }, set: { if !$0 { healthKitError = nil } })) {
                Button("OK") { healthKitError = nil }
            } message: {
                Text(healthKitError ?? "")
            }
            .alert("Export fehlgeschlagen", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var healthKitBinding: Binding<Bool> {
        Binding(
            get: { settings.healthKitSyncEnabled },
            set: { enabled in
                if enabled {
                    enableHealthKit()
                } else {
                    settings.healthKitSyncEnabled = false
                }
            }
        )
    }

    private var healthKitStatusText: String {
        guard HealthKitManager.shared.isAvailable else { return "Nicht verfügbar" }
        switch HealthKitManager.shared.authorizationStatus {
        case .sharingAuthorized: return settings.healthKitSyncEnabled ? "Verbunden" : "Berechtigt, Sync aus"
        case .sharingDenied: return "In Health abgelehnt"
        default: return "Noch nicht angefragt"
        }
    }

    private func enableHealthKit() {
        isRequestingHealthKit = true
        Task {
            defer { isRequestingHealthKit = false }
            do {
                try await HealthKitManager.shared.requestAuthorization()
                if HealthKitManager.shared.isAuthorizedToWrite {
                    settings.healthKitSyncEnabled = true
                    try? nutritionLog.syncPendingEntries()
                } else {
                    settings.healthKitSyncEnabled = false
                    healthKitError = "Die Schreibberechtigung wurde nicht erteilt. Du kannst sie in der Health-App unter „Datenzugriff & Geräte“ ändern."
                }
            } catch {
                settings.healthKitSyncEnabled = false
                healthKitError = error.localizedDescription
            }
        }
    }

    private func goalStepper(_ title: String, unit: String, value: Int, range: ClosedRange<Int>, step: Int, onChange: @escaping (Int) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: onChange), in: range, step: step) {
            LabeledContent(title, value: "\(value) \(unit)")
        }
    }

    private func exportRecipes() {
        do {
            let data = try coordinator.repository.exportJSON()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Rezepte-\(formatter.string(from: .now)).json")
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(ImportCoordinator.preview)
        .environment(NutritionLogService.preview)
        .modelContainer(RecipeSchemaV1.previewContainer())
}
