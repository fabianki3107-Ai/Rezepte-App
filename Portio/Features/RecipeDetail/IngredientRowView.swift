import SwiftUI

/// Interaktive Zutatenzeile: Antippen hakt ab (Einkauf/Vorbereitung), Menge ist bereits skaliert.
struct IngredientRowView: View {
    let ingredient: Ingredient
    let scaler: ServingsScaler
    let isChecked: Bool
    let onToggle: () -> Void

    private var amountText: String {
        QuantityFormatter.string(for: scaler.scale(ingredient.measure))
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? AppTheme.trust : AppTheme.secondaryLabel)
                    .symbolEffect(.bounce, value: isChecked)

                if !amountText.isEmpty {
                    Text(amountText)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(scaler.isScaled && ingredient.isScalable ? AppTheme.accent : AppTheme.label)
                        .frame(minWidth: 64, alignment: .trailing)
                        .contentTransition(.numericText())
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(ingredient.name)
                            .font(.body)
                        if ingredient.isOptional {
                            Text("optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.tertiaryBackground, in: Capsule())
                        }
                    }
                    if let note = ingredient.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .strikethrough(isChecked, color: AppTheme.secondaryLabel)
                .foregroundStyle(isChecked ? AppTheme.secondaryLabel : AppTheme.label)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .frame(minHeight: AppTheme.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(amountText) \(ingredient.name)")
        .accessibilityValue(isChecked ? "abgehakt" : "offen")
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isChecked)
    }
}
