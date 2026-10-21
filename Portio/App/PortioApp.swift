import SwiftUI
import SwiftData

/// Einstiegspunkt der App.
///
/// Der `ModelContainer` wird bewusst mit `cloudKitDatabase: .none` erzeugt:
/// Alle Daten bleiben ausschließlich auf dem Gerät (Local-First, keine Cloud).
@main
struct PortioApp: App {
    private let container: ModelContainer
    @State private var importCoordinator: ImportCoordinator
    @State private var inboxService: ImportInboxService
    @State private var nutritionLog: NutritionLogService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try Self.makeContainer()
        } catch {
            // Ein nicht ladbarer Store ist ein Programmierfehler (Schema-Migration vergessen),
            // kein Laufzeitzustand, den der Nutzer beheben könnte.
            fatalError("SwiftData-Container konnte nicht erstellt werden: \(error)")
        }
        let repository = RecipeRepository(modelContainer: container)
        _importCoordinator = State(initialValue: ImportCoordinator(repository: repository))
        _inboxService = State(initialValue: ImportInboxService())
        _nutritionLog = State(initialValue: NutritionLogService(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(importCoordinator)
                .environment(inboxService)
                .environment(nutritionLog)
                .tint(AppTheme.accent)
                .onOpenURL { url in
                    importCoordinator.handle(incomingURL: url)
                }
                .task(id: scenePhase) {
                    // Beim Aktivwerden Share-Extension-Eingang abholen (App Group Inbox).
                    guard scenePhase == .active else { return }
                    let items = await inboxService.drain()
                    if let first = items.first {
                        await importCoordinator.handle(inboxItem: first)
                    }
                }
        }
        .modelContainer(container)
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(RecipeSchemaV1.models)
        let configuration = ModelConfiguration(
            "PortioStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// Zentrale Schema-Definition, damit App, Tests und Previews dieselbe Modellliste nutzen.
enum RecipeSchemaV1 {
    static let models: [any PersistentModel.Type] = [
        RecipeItem.self,
        Ingredient.self,
        CookingStep.self,
        Tag.self,
        DailyLog.self,
        LogEntry.self
    ]

    /// In-Memory-Container für Previews und Tests.
    @MainActor
    static func previewContainer(seeded: Bool = true) -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        if seeded {
            let context = container.mainContext
            for recipe in RecipeItem.sampleRecipes() {
                context.insert(recipe)
            }
            try? context.save()
        }
        return container
    }
}
