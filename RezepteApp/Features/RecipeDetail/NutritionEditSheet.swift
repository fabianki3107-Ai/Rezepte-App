import SwiftUI

/// Manuelle Eingabe der Nährwerte pro Portion – mit Plausibilitätshinweis aus den Makros.
struct NutritionEditSheet: View {
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(\.dismiss) private var dismiss
    let recipe: RecipeItem

    @State private var calories: Int?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var estimate: NutritionEstimate?

    private var facts: NutritionFacts {
        NutritionFacts(calories: Double(calories ?? 0), protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
    }

    private var macroCalories: Int { Int(facts.caloriesFromMacros.rounded()) }
    private var deviatesFromMacros: Bool {
        guard let calories, calories > 0, macroCalories > 0 else { return false }
        return abs(Double(calories - macroCalories)) / Double(calories) > 0.25
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    numberRow("Kalorien", unit: "kcal", value: $calories)
                    decimalRow("Eiweiß", value: $protein)
                    decimalRow("Kohlenhydrate", value: $carbs)
                    decimalRow("Fett", value: $fat)
                } header: {
                    Text("Pro Portion (\(recipe.servings) Portionen im Rezept)")
                } footer: {
                    if deviatesFromMacros {
                        Label("Aus den Makros ergeben sich etwa \(macroCalories) kcal – bitte prüfen.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.warning)
                    } else {
                        Text("Aus den Makros: ≈ \(macroCalories) kcal (4/4/9-Regel).")
                    }
                }

                if let estimate, estimate.isUsable {
                    Section("Lokale Schätzung") {
                        LabeledContent("Vorschlag", value: "\(Int(estimate.perServing.calories)) kcal · E \(Int(estimate.perServing.protein)) · K \(Int(estimate.perServing.carbs)) · F \(Int(estimate.perServing.fat))")
                            .font(.footnote)
                        Button("Vorschlag übernehmen") {
                            apply(estimate.perServing)
                        }
                        if !estimate.unmatchedNames.isEmpty {
                            Text("Nicht zugeordnet: \(estimate.unmatchedNames.joined(separator: ", "))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Nährwerte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        try? importCoordinator.repository.setManualNutrition(recipe, facts: facts)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled((calories ?? 0) <= 0)
                }
            }
            .onAppear {
                apply(recipe.nutrition)
                estimate = LocalNutritionParser.estimate(recipe: recipe)
            }
        }
    }

    private func apply(_ values: NutritionFacts) {
        calories = Int(values.calories.rounded())
        protein = values.protein
        carbs = values.carbs
        fat = values.fat
    }

    private func numberRow(_ title: String, unit: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func decimalRow(_ title: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("g").foregroundStyle(.secondary)
        }
    }
}
