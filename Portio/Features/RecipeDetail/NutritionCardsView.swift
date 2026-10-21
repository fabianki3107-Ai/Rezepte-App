import SwiftUI

/// Nährwert-Karten pro Portion (kcal, Eiweiß, Kohlenhydrate, Fett) mit Herkunfts-/Vertrauens-Badge.
struct NutritionCardsView: View {
    let recipe: RecipeItem
    var onEdit: (() -> Void)? = nil
    var onRecalculate: (() -> Void)? = nil

    private var facts: NutritionFacts { recipe.nutrition }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack {
                Text("Nährwerte pro Portion")
                    .font(.title3.weight(.semibold))
                Spacer()
                if onEdit != nil || onRecalculate != nil {
                    Menu {
                        if let onEdit {
                            Button("Werte bearbeiten", systemImage: "pencil", action: onEdit)
                        }
                        if let onRecalculate {
                            Button("Aus Zutaten neu schätzen", systemImage: "arrow.clockwise", action: onRecalculate)
                        }
                    } label: {
                        Label("Nährwerte anpassen", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                }
            }

            if recipe.hasNutrition {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.m) {
                    NutritionCard(title: "Kalorien", value: "\(recipe.caloriesPerServing)", unit: "kcal", systemImage: "flame.fill", tint: AppTheme.accent)
                    ForEach(Macro.allCases) { macro in
                        NutritionCard(
                            title: macro.title,
                            value: QuantityFormatter.number(facts.value(for: macro), unit: .gram),
                            unit: "g",
                            systemImage: macro.symbolName,
                            tint: macro.color
                        )
                    }
                }
                NutritionTrustBadge(recipe: recipe)
            } else {
                HStack(spacing: AppTheme.Spacing.m) {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noch keine Nährwerte")
                            .font(.headline)
                        Text("Die Zutaten konnten nicht zugeordnet werden. Trage die Werte ein oder lass sie neu schätzen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(AppTheme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
            }
        }
    }
}

private struct NutritionCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

/// Badge zur Herkunft der Nährwerte: Mint bei verlässlicher Schätzung, Orange bei grober.
struct NutritionTrustBadge: View {
    let recipe: RecipeItem

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            switch recipe.nutritionSource {
            case .manual:
                TrustBadgeView(style: .trusted("Manuell geprüft", systemImage: "checkmark.seal.fill"))
            case .declared:
                TrustBadgeView(style: .trusted("Aus dem Rezept übernommen", systemImage: "doc.text.magnifyingglass"))
            case .estimated:
                if recipe.nutritionConfidence >= NutritionEstimate.goodConfidenceThreshold {
                    TrustBadgeView(style: .trusted("Gute Schätzung · \(Int(recipe.nutritionConfidence * 100)) %", systemImage: "scalemass.fill"))
                } else {
                    TrustBadgeView(style: .review("Grobe Schätzung · \(Int(recipe.nutritionConfidence * 100)) %", systemImage: "scalemass"))
                }
            case .none:
                TrustBadgeView(style: .neutral("Nicht berechnet", systemImage: "circle.dashed"))
            }
            Spacer()
            Text("Lokal berechnet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScrollView {
        NutritionCardsView(recipe: RecipeItem.sampleRecipes()[0], onEdit: {}, onRecalculate: {})
            .padding()
    }
    .background(AppTheme.background)
}
