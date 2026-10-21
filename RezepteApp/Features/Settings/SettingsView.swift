import SwiftUI
import SwiftData

/// Einstellungen: Datenschutz-Status, Verhalten im Koch-Modus, lokaler Export, Löschen.
struct SettingsView: View {
    @Environment(ImportCoordinator.self) private var coordinator
    @Query private var recipes: [Recipe]
    @State private var settings = AppSettings.shared
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
                    Toggle("Instagram-Beitrag direkt laden", isOn: $settings.loadInstagramPreview)
                } header: {
                    Text("Import")
                } footer: {
                    Text("Wenn aktiv, lädt die App beim Link-Import die Beitragsseite direkt von instagram.com – wie ein Browser, ohne Zwischenserver. Deaktiviert: Link wird nur als Quelle gespeichert, Inhalte kommen per Screenshot oder Einfügen.")
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
            .alert("Export fehlgeschlagen", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
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
        .modelContainer(RecipeSchemaV1.previewContainer())
}
