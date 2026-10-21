import SwiftUI
import SwiftData

/// Rezept-Bibliothek: Suche über Titel, Zutaten und Tags; Sortierung; Favoriten-Filter.
struct LibraryView: View {
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .recentlyUpdated
    @State private var favoritesOnly = false

    enum SortOrder: String, CaseIterable, Identifiable {
        case recentlyUpdated = "Zuletzt bearbeitet"
        case title = "Titel"
        case recentlyCooked = "Zuletzt gekocht"
        case quickest = "Schnellste zuerst"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            FilteredRecipeList(searchText: searchText, sortOrder: sortOrder, favoritesOnly: favoritesOnly)
                .navigationTitle("Bibliothek")
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Rezepte, Zutaten, Tags")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sortierung", selection: $sortOrder) {
                                ForEach(SortOrder.allCases) { order in
                                    Text(order.rawValue).tag(order)
                                }
                            }
                            Divider()
                            Toggle("Nur Favoriten", isOn: $favoritesOnly)
                        } label: {
                            Label("Sortieren und filtern", systemImage: favoritesOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe)
                }
        }
    }
}

/// Eigene View, damit `@Query` mit dynamischem Prädikat initialisiert werden kann.
private struct FilteredRecipeList: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Query private var recipes: [Recipe]

    private let searchText: String
    private let sortOrder: LibraryView.SortOrder
    private let favoritesOnly: Bool

    init(searchText: String, sortOrder: LibraryView.SortOrder, favoritesOnly: Bool) {
        self.searchText = searchText
        self.sortOrder = sortOrder
        self.favoritesOnly = favoritesOnly

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let predicate: Predicate<Recipe>?
        switch (trimmed.isEmpty, favoritesOnly) {
        case (true, false):
            predicate = nil
        case (true, true):
            predicate = #Predicate { $0.isFavorite }
        case (false, false):
            predicate = #Predicate { recipe in
                recipe.title.localizedStandardContains(trimmed)
                || recipe.ingredients.contains(where: { $0.name.localizedStandardContains(trimmed) })
                || recipe.tags.contains(where: { $0.name.localizedStandardContains(trimmed) })
            }
        case (false, true):
            predicate = #Predicate { recipe in
                recipe.isFavorite && (
                    recipe.title.localizedStandardContains(trimmed)
                    || recipe.ingredients.contains(where: { $0.name.localizedStandardContains(trimmed) })
                    || recipe.tags.contains(where: { $0.name.localizedStandardContains(trimmed) })
                )
            }
        }

        let sort: [SortDescriptor<Recipe>]
        switch sortOrder {
        case .recentlyUpdated: sort = [SortDescriptor(\Recipe.updatedAt, order: .reverse)]
        case .title: sort = [SortDescriptor(\Recipe.title, comparator: .localizedStandard)]
        case .recentlyCooked: sort = [SortDescriptor(\Recipe.lastCookedAt, order: .reverse), SortDescriptor(\Recipe.updatedAt, order: .reverse)]
        case .quickest: sort = [SortDescriptor(\Recipe.cookTimeMinutes), SortDescriptor(\Recipe.prepTimeMinutes)]
        }
        _recipes = Query(filter: predicate, sort: sort, animation: .default)
    }

    var body: some View {
        Group {
            if recipes.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCardView(recipe: recipe)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                try? importCoordinator.repository.toggleFavorite(recipe)
                            } label: {
                                Label(recipe.isFavorite ? "Favorit entfernen" : "Favorit", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                            }
                            .tint(AppTheme.destructive)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                try? importCoordinator.repository.delete(recipe)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
            }
        }
        .background(AppTheme.background)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(searchText.isEmpty ? "Noch keine Rezepte" : "Keine Treffer", systemImage: searchText.isEmpty ? "book.closed" : "magnifyingglass")
        } description: {
            Text(searchText.isEmpty
                 ? "Importiere dein erstes Rezept per Screenshot, Foto oder Instagram-Link. Alles bleibt auf deinem Gerät."
                 : "Für „\(searchText)“ wurde nichts gefunden.")
        } actions: {
            if searchText.isEmpty {
                Button("Beispielrezepte hinzufügen") {
                    for recipe in Recipe.sampleRecipes() {
                        modelContext.insert(recipe)
                    }
                    try? modelContext.save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    LibraryView()
        .environment(ImportCoordinator.preview)
        .modelContainer(RecipeSchemaV1.previewContainer())
}
