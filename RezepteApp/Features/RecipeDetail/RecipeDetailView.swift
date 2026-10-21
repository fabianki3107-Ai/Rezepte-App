import SwiftUI
import SwiftData

/// Rezept-Detailansicht: Hero-Bild, Metadaten, Portionen-Skalierer, interaktive Zutaten, Schritte.
struct RecipeDetailView: View {
    @Bindable var recipe: RecipeItem
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(NutritionLogService.self) private var nutritionLog
    @Environment(\.dismiss) private var dismiss

    @State private var scaler: ServingsScaler
    @State private var showNutritionEditor = false
    @State private var toast: NutritionLogService.Confirmation?
    @State private var logError: String?
    @State private var checkedIngredientIDs: Set<UUID> = []
    @State private var showCookingMode = false
    @State private var showDeleteConfirmation = false
    @State private var showRawText = false

    init(recipe: RecipeItem) {
        self.recipe = recipe
        _scaler = State(initialValue: ServingsScaler(baseServings: recipe.servings))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
                heroImage
                header
                ServingsScalerView(scaler: $scaler)
                NutritionCardsView(
                    recipe: recipe,
                    onEdit: { showNutritionEditor = true },
                    onRecalculate: { _ = try? importCoordinator.repository.recalculateNutrition(recipe, overrideManual: true) }
                )
                ingredientsSection
                stepsSection
                if let notes = recipe.notes, !notes.isEmpty { notesSection(notes) }
                sourceSection
            }
            .padding(.horizontal, AppTheme.Spacing.l)
            .padding(.bottom, 96)
        }
        .background(AppTheme.background)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { actionBar }
        .overlay(alignment: .top) { toastView }
        .sheet(isPresented: $showNutritionEditor) {
            NutritionEditSheet(recipe: recipe)
                .presentationDetents([.large])
        }
        .alert("Loggen fehlgeschlagen", isPresented: Binding(get: { logError != nil }, set: { if !$0 { logError = nil } })) {
            Button("OK") { logError = nil }
        } message: {
            Text(logError ?? "")
        }
        .fullScreenCover(isPresented: $showCookingMode) {
            CookingModeView(
                session: CookingSession(recipe: recipe, scaler: scaler, checkedIngredientIDs: checkedIngredientIDs),
                onFinish: { finishedChecked in
                    checkedIngredientIDs = finishedChecked
                    try? importCoordinator.repository.markCooked(recipe)
                }
            )
        }
        .confirmationDialog("Rezept löschen?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                try? importCoordinator.repository.delete(recipe)
                dismiss()
            }
        } message: {
            Text("„\(recipe.title)“ wird dauerhaft von diesem Gerät entfernt.")
        }
    }

    // MARK: - Abschnitte

    @ViewBuilder
    private var heroImage: some View {
        if let data = recipe.heroImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                .accessibilityLabel("Rezeptbild")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Text(recipe.title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: AppTheme.Spacing.s) {
                TrustBadgeView(recipe: recipe)
                if let total = recipe.totalTimeMinutes {
                    metaChip("\(total) Min", systemImage: "clock")
                }
                metaChip(recipe.difficulty.title, systemImage: "chart.bar")
            }
            .padding(.top, AppTheme.Spacing.xs)

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.s) {
                        ForEach(recipe.tags.sorted { $0.name < $1.name }, id: \.name) { tag in
                            Text("#\(tag.name)")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, AppTheme.Spacing.s)
                                .padding(.vertical, AppTheme.Spacing.xs)
                                .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func metaChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.s)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.secondaryBackground, in: Capsule())
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            sectionHeader("Zutaten", trailing: checkedIngredientIDs.isEmpty ? nil : "Zurücksetzen") {
                withAnimation { checkedIngredientIDs.removeAll() }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recipe.ingredientGroups.enumerated()), id: \.offset) { _, group in
                    if let title = group.title {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, AppTheme.Spacing.m)
                            .padding(.bottom, AppTheme.Spacing.xs)
                    }
                    ForEach(group.items, id: \.id) { ingredient in
                        IngredientRowView(
                            ingredient: ingredient,
                            scaler: scaler,
                            isChecked: checkedIngredientIDs.contains(ingredient.id)
                        ) {
                            toggle(ingredient)
                        }
                        if ingredient.id != group.items.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.l)
            .padding(.vertical, AppTheme.Spacing.s)
            .cardBackground()

            if scaler.isScaled {
                Label("Mengen für \(scaler.targetServings) Portionen umgerechnet. Gewürze bleiben nach Geschmack.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            sectionHeader("Zubereitung")
            VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
                ForEach(Array(recipe.sortedSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: AppTheme.Spacing.m) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.accent, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(step.text)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: AppTheme.Spacing.s) {
                                if let seconds = step.durationSeconds, seconds > 0 {
                                    Label(DurationFormatting.short(seconds), systemImage: "timer")
                                }
                                if let temperature = step.temperatureCelsius {
                                    Label("\(temperature) °C", systemImage: "thermometer.medium")
                                }
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Schritt \(index + 1): \(step.text)")
                }
            }
            .padding(AppTheme.Spacing.l)
            .cardBackground()
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            sectionHeader("Tipps & Notizen")
            Text(notes)
                .font(.body)
                .padding(AppTheme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            sectionHeader("Quelle")
            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                Label {
                    Text(recipe.source.kind.title)
                    if let author = recipe.sourceAuthor { Text("· \(author)").foregroundStyle(.secondary) }
                } icon: {
                    Image(systemName: recipe.source.kind.symbolName)
                }
                if let url = recipe.sourceURL {
                    Link(destination: url) {
                        Label("Original öffnen", systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                }
                OfflineBadgeView()
                if recipe.verification == .unverified {
                    Button {
                        try? importCoordinator.repository.markVerified(recipe)
                    } label: {
                        Label("Als geprüft markieren", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.trust)
                    .padding(.top, AppTheme.Spacing.xs)
                }
            }
            .padding(AppTheme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    private func sectionHeader(_ title: String, trailing: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action)
                    .font(.subheadline)
            }
        }
    }

    /// Primäraktion: 1-Tap-Log einer Portion. Langes Drücken öffnet weitere Portionsgrößen.
    private var actionBar: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Menu {
                ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { portions in
                    Button {
                        logToday(servings: portions)
                    } label: {
                        Label(
                            "\(ServingsFormatting.string(portions)) · \(Int(recipe.nutrition.scaled(by: portions).calories.rounded())) kcal",
                            systemImage: portions == 1 ? "plus.circle.fill" : "plus.circle"
                        )
                    }
                }
            } label: {
                Label(recipe.hasNutrition ? "Heute loggen · \(recipe.caloriesPerServing) kcal" : "Heute loggen", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            } primaryAction: {
                logToday(servings: 1)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!recipe.hasNutrition)
            .accessibilityHint("Trägt eine Portion in das heutige Tagebuch ein. Lange drücken für andere Portionsgrößen.")

            Button {
                showCookingMode = true
            } label: {
                Label("Kochen", systemImage: "play.fill")
                    .font(.headline)
                    .frame(minHeight: 50)
                    .padding(.horizontal, AppTheme.Spacing.s)
            }
            .buttonStyle(.bordered)
            .disabled(recipe.steps.isEmpty)
        }
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.vertical, AppTheme.Spacing.s)
        .background(.bar)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label {
                Text("Geloggt · \(Int(toast.facts.calories)) kcal")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.l)
            .padding(.vertical, AppTheme.Spacing.m)
            .background(AppTheme.trust, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.top, AppTheme.Spacing.s)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.snappy) { self.toast = nil }
            }
            .accessibilityAddTraits(.isStaticText)
        }
    }

    private func logToday(servings: Double) {
        do {
            try nutritionLog.log(recipe, servings: servings)
            withAnimation(.snappy) { toast = nutritionLog.lastConfirmation }
        } catch {
            logError = error.localizedDescription
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                try? importCoordinator.repository.toggleFavorite(recipe)
            } label: {
                Label(recipe.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten", systemImage: recipe.isFavorite ? "heart.fill" : "heart")
            }
            .tint(recipe.isFavorite ? AppTheme.destructive : AppTheme.accent)
            .sensoryFeedback(.success, trigger: recipe.isFavorite)

            Menu {
                ShareLink(item: ShareableRecipeText.make(recipe), preview: SharePreview(recipe.title)) {
                    Label("Als Text teilen", systemImage: "square.and.arrow.up")
                }
                Button {
                    showNutritionEditor = true
                } label: {
                    Label("Nährwerte bearbeiten", systemImage: "flame")
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Label("Mehr", systemImage: "ellipsis.circle")
            }
        }
    }

    private func toggle(_ ingredient: Ingredient) {
        withAnimation(.snappy) {
            if checkedIngredientIDs.contains(ingredient.id) {
                checkedIngredientIDs.remove(ingredient.id)
            } else {
                checkedIngredientIDs.insert(ingredient.id)
            }
        }
    }
}

/// Erzeugt einen Klartext zum Teilen (Nachrichten, Notizen) – ohne Serverbeteiligung.
enum ShareableRecipeText {
    @MainActor
    static func make(_ recipe: RecipeItem) -> String {
        var lines = [recipe.title, ""]
        if recipe.hasNutrition {
            lines.append("Pro Portion: \(recipe.caloriesPerServing) kcal · \(Int(recipe.proteinGrams)) g Eiweiß · \(Int(recipe.carbsGrams)) g Kohlenhydrate · \(Int(recipe.fatGrams)) g Fett")
            lines.append("")
        }
        lines.append("Zutaten (\(recipe.servings) Portionen):")
        for ingredient in recipe.sortedIngredients {
            let amount = QuantityFormatter.string(for: ingredient.measure)
            lines.append("• " + [amount, ingredient.name].filter { !$0.isEmpty }.joined(separator: " "))
        }
        lines.append("")
        lines.append("Zubereitung:")
        for (index, step) in recipe.sortedSteps.enumerated() {
            lines.append("\(index + 1). \(step.text)")
        }
        if let url = recipe.sourceURL {
            lines.append("")
            lines.append("Quelle: \(url.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }
}

enum DurationFormatting {
    /// "1 Std 10 Min", "6 Min", "45 Sek".
    static func short(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) Sek" }
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours) Std" : "\(hours) Std \(rest) Min"
        }
        return "\(minutes) Min"
    }

    /// "04:35" für laufende Timer.
    static func clock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: RecipeItem.sampleShakshuka())
    }
    .environment(ImportCoordinator.preview)
    .environment(NutritionLogService.preview)
    .modelContainer(RecipeSchemaV1.previewContainer())
}
