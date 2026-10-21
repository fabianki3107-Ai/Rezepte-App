import SwiftUI

/// Prüf- und Korrekturansicht vor dem Speichern. Zeigt Warnungen, erlaubt Bearbeitung aller Felder.
struct ImportReviewView: View {
    @Environment(ImportCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ParsedRecipeDraft
    @State private var newIngredientText = ""
    @State private var newStepText = ""
    @State private var showRawText = false
    @State private var saveError: String?

    init(draft: ParsedRecipeDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                warningsSection
                basicsSection
                ingredientsSection
                stepsSection
                nutritionPreviewSection
                sourceSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Rezept prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Verwerfen", role: .destructive) {
                        coordinator.reset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save)
                        .fontWeight(.semibold)
                        .disabled(!draft.isSaveable)
                }
            }
            .alert("Speichern fehlgeschlagen", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Abschnitte

    @ViewBuilder
    private var warningsSection: some View {
        if !draft.warnings.isEmpty {
            Section {
                ForEach(draft.warnings) { warning in
                    Label {
                        Text(warning.message).font(.subheadline)
                    } icon: {
                        Image(systemName: warning.isBlocking ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .foregroundStyle(warning.isBlocking ? AppTheme.warning : AppTheme.accent)
                    }
                }
            }
        } else if let confidence = draft.ocrConfidence {
            Section {
                TrustBadgeView(style: .trusted("Texterkennung \(Int(confidence * 100)) % sicher", systemImage: "checkmark.seal.fill"))
            }
        }
    }

    private var basicsSection: some View {
        Section("Rezept") {
            if let data = draft.heroImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            draft.heroImageData = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(6)
                        .accessibilityLabel("Bild entfernen")
                    }
            }
            TextField("Titel", text: $draft.title)
                .font(.headline)
            TextField("Kurzbeschreibung", text: Binding($draft.summary, replacingNilWith: ""), axis: .vertical)
                .lineLimit(1...3)
            Stepper(value: Binding(get: { draft.servings ?? 4 }, set: { draft.servings = $0 }), in: ServingsScaler.range) {
                LabeledContent("Portionen", value: "\(draft.servings ?? 4)")
            }
            minutesField("Vorbereitung", value: $draft.prepTimeMinutes)
            minutesField("Koch-/Backzeit", value: $draft.cookTimeMinutes)
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach($draft.ingredients) { $ingredient in
                IngredientEditRow(ingredient: $ingredient)
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            .onMove { draft.ingredients.move(fromOffsets: $0, toOffset: $1) }

            HStack {
                TextField("z. B. 200 g Mehl", text: $newIngredientText)
                    .submitLabel(.done)
                    .onSubmit(addIngredient)
                Button("Hinzufügen", action: addIngredient)
                    .disabled(newIngredientText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            HStack {
                Text("Zutaten (\(draft.ingredients.count))")
                Spacer()
                EditButton().font(.footnote)
            }
        } footer: {
            Text("Menge und Einheit werden automatisch erkannt. Tippe eine Zeile an, um sie zu korrigieren.")
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach($draft.steps) { $step in
                HStack(alignment: .top, spacing: AppTheme.Spacing.m) {
                    Text("\((draft.steps.firstIndex { $0.id == step.id } ?? 0) + 1)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Schritt", text: $step.text, axis: .vertical)
                            .lineLimit(1...6)
                            .onChange(of: step.text) { _, text in
                                let annotations = StepAnnotator.annotate(text)
                                step.durationSeconds = annotations.durationSeconds
                                step.temperatureCelsius = annotations.temperatureCelsius
                            }
                        HStack(spacing: AppTheme.Spacing.s) {
                            if let seconds = step.durationSeconds, seconds > 0 {
                                Label(DurationFormatting.short(seconds), systemImage: "timer")
                            }
                            if let temperature = step.temperatureCelsius {
                                Label("\(temperature) °C", systemImage: "thermometer.medium")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }

            HStack(alignment: .top) {
                TextField("Neuen Schritt beschreiben", text: $newStepText, axis: .vertical)
                    .lineLimit(1...4)
                Button("Hinzufügen", action: addStep)
                    .disabled(newStepText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Zubereitung (\(draft.steps.count))")
        } footer: {
            Text("Zeitangaben wie „10 Minuten“ werden im Koch-Modus zu Timern.")
        }
    }

    /// Live-Vorschau der lokalen Nährwert-Schätzung – zeigt sofort, was nach dem Speichern geloggt würde.
    private var nutritionPreviewSection: some View {
        let estimate = LocalNutritionParser.estimate(draft: draft)
        return Section {
            if estimate.isUsable {
                LabeledContent("Kalorien", value: "\(Int(estimate.perServing.calories)) kcal")
                LabeledContent("Eiweiß / Kohlenhydrate / Fett", value: "\(Int(estimate.perServing.protein)) · \(Int(estimate.perServing.carbs)) · \(Int(estimate.perServing.fat)) g")
                HStack {
                    if estimate.source == .declared {
                        TrustBadgeView(style: .trusted("Aus dem Rezepttext übernommen", systemImage: "doc.text.magnifyingglass"))
                    } else if estimate.confidence >= NutritionEstimate.goodConfidenceThreshold {
                        TrustBadgeView(style: .trusted("Gute Schätzung · \(Int(estimate.confidence * 100)) %", systemImage: "scalemass.fill"))
                    } else {
                        TrustBadgeView(style: .review("Grobe Schätzung · \(Int(estimate.confidence * 100)) %", systemImage: "scalemass"))
                    }
                }
                if !estimate.unmatchedNames.isEmpty {
                    Text("Nicht zugeordnet: \(estimate.unmatchedNames.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Noch keine Schätzung möglich – Zutaten mit Mengen ergänzen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Nährwerte pro Portion (lokal geschätzt)")
        } footer: {
            Text("Nach dem Speichern kannst du die Werte im Rezept jederzeit korrigieren.")
        }
    }

    private var sourceSection: some View {
        Section("Quelle") {
            LabeledContent("Import", value: draft.source.kind.title)
            if let url = draft.source.url {
                Link(destination: url) { LabeledContent("Link", value: url.host ?? url.absoluteString) }
            }
            TextField("Autor*in (optional)", text: Binding($draft.sourceAuthor, replacingNilWith: ""))
            if !draft.tags.isEmpty {
                LabeledContent("Tags", value: draft.tags.map { "#\($0)" }.joined(separator: " "))
                    .lineLimit(2)
            }
            if !draft.rawText.isEmpty {
                DisclosureGroup("Erkannter Originaltext", isExpanded: $showRawText) {
                    Text(draft.rawText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Aktionen

    private func minutesField(_ title: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text("Min").foregroundStyle(.secondary)
        }
    }

    private func addIngredient() {
        guard let ingredient = DraftIngredient.from(line: newIngredientText, group: draft.ingredients.last?.group) else { return }
        withAnimation {
            draft.ingredients.append(ingredient)
            draft.warnings.removeAll { $0 == .noIngredientsFound }
        }
        newIngredientText = ""
    }

    private func addStep() {
        let text = newStepText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation {
            draft.steps.append(.from(text: text.capitalizingFirstLetter))
            draft.warnings.removeAll { $0 == .noStepsFound }
        }
        newStepText = ""
    }

    private func save() {
        do {
            try coordinator.save(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Zutatenzeile im Review: Freitext, der beim Bestätigen neu geparst wird.
private struct IngredientEditRow: View {
    @Binding var ingredient: DraftIngredient
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Zutat", text: $text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            if let group = ingredient.group {
                Text(group).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { text = ingredient.displayText }
    }

    private func commit() {
        guard let parsed = DraftIngredient.from(line: text, group: ingredient.group) else { return }
        var updated = parsed
        updated.id = ingredient.id
        ingredient = updated
        text = updated.displayText
    }
}

extension Binding where Value == String {
    /// Bindet ein optionales String-Feld an ein `TextField`.
    init(_ source: Binding<String?>, replacingNilWith placeholder: String) {
        self.init(
            get: { source.wrappedValue ?? placeholder },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

#Preview {
    ImportReviewView(draft: RecipeTextParser.parse(
        """
        Cremige Tomatenpasta 🍝
        Zutaten für 2 Personen:
        250 g Spaghetti
        1 Dose Tomaten (400 g)
        2 Knoblauchzehen
        100 ml Sahne
        Salz, Pfeffer
        Zubereitung:
        1. Nudeln 9 Minuten kochen.
        2. Knoblauch anbraten, Tomaten zugeben, 10 Minuten köcheln.
        3. Sahne unterrühren, mit den Nudeln vermengen.
        #pasta #vegetarisch
        """,
        source: .screenshot,
        ocrConfidence: 0.91
    ))
    .environment(ImportCoordinator.preview)
}
