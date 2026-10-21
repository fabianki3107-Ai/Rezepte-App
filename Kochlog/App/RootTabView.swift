import SwiftUI

/// Hauptnavigation nach HIG: Tab Bar mit maximal fünf klar benannten Bereichen.
struct RootTabView: View {
    @Environment(ImportCoordinator.self) private var importCoordinator
    @State private var selection: Tab = .today

    enum Tab: Hashable {
        case today, library, importHub, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Heute", systemImage: "chart.pie") }
                .tag(Tab.today)

            LibraryView()
                .tabItem { Label("Bibliothek", systemImage: "book.closed") }
                .tag(Tab.library)

            ImportHubView()
                .tabItem { Label("Importieren", systemImage: "square.and.arrow.down") }
                .tag(Tab.importHub)

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onChange(of: importCoordinator.phase.isActive) { _, isActive in
            // Wenn ein Import von außen (Share Sheet / URL) hereinkommt, zum Import-Tab springen.
            if isActive { selection = .importHub }
        }
    }
}

#Preview {
    RootTabView()
        .environment(ImportCoordinator.preview)
        .environment(ImportInboxService())
        .environment(NutritionLogService.preview)
        .modelContainer(RecipeSchemaV1.previewContainer())
}
