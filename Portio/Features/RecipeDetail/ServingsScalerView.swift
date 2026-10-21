import SwiftUI

/// Portionen-Skalierer: Stepper mit großen Touch-Zielen, Reset auf Originalportionen.
struct ServingsScalerView: View {
    @Binding var scaler: ServingsScaler

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Portionen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.s) {
                    Text("\(scaler.targetServings)")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    if scaler.isScaled {
                        Button {
                            withAnimation(.snappy) { scaler.reset() }
                        } label: {
                            Text("Original: \(scaler.baseServings)")
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("Auf Originalportionen zurücksetzen")
                    }
                }
            }

            Spacer()

            HStack(spacing: 0) {
                stepButton(systemImage: "minus", enabled: scaler.targetServings > ServingsScaler.range.lowerBound) {
                    scaler.decrement()
                }
                Divider().frame(height: 24)
                stepButton(systemImage: "plus", enabled: scaler.targetServings < ServingsScaler.range.upperBound) {
                    scaler.increment()
                }
            }
            .background(AppTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Portionen")
            .accessibilityValue("\(scaler.targetServings)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: scaler.increment()
                case .decrement: scaler.decrement()
                @unknown default: break
                }
            }
        }
        .padding(AppTheme.Spacing.l)
        .cardBackground()
        .sensoryFeedback(.selection, trigger: scaler.targetServings)
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: AppTheme.minimumTapTarget + 8, height: AppTheme.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AppTheme.accent : AppTheme.secondaryLabel)
        .disabled(!enabled)
    }
}

#Preview {
    struct Host: View {
        @State var scaler = ServingsScaler(baseServings: 4, targetServings: 6)
        var body: some View { ServingsScalerView(scaler: $scaler).padding().background(AppTheme.background) }
    }
    return Host()
}
