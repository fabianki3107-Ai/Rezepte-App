import SwiftUI

/// Ablenkungsfreier Koch-Modus: ein Schritt pro Seite, große Schrift, Timer, Bildschirm bleibt an.
struct CookingModeView: View {
    @State var session: CookingSession
    let onFinish: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showIngredients = false
    @State private var showFinished = false
    @State private var timerAlertStepID: UUID?

    private let settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    ProgressView(value: session.progress)
                        .tint(AppTheme.accent)
                        .padding(.horizontal, AppTheme.Spacing.l)
                        .accessibilityLabel("Fortschritt")
                        .accessibilityValue("Schritt \(session.currentStepIndex + 1) von \(session.steps.count)")

                    TabView(selection: $session.currentStepIndex) {
                        ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                            CookingStepPage(session: session, step: step, index: index, now: context.date)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.snappy, value: session.currentStepIndex)

                    navigationBar
                }
                .onChange(of: context.date) { _, now in
                    session.tick(now: now)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Schritt \(session.currentStepIndex + 1) von \(session.steps.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Beenden") { leave() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showIngredients = true
                    } label: {
                        Label("Zutaten", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .sheet(isPresented: $showIngredients) {
                CookingIngredientsSheet(session: session)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Timer abgelaufen", isPresented: Binding(get: { timerAlertStepID != nil }, set: { if !$0 { timerAlertStepID = nil } })) {
                Button("OK") { timerAlertStepID = nil }
            } message: {
                if let id = timerAlertStepID, let index = session.steps.firstIndex(where: { $0.id == id }) {
                    Text("Schritt \(index + 1) ist fertig.")
                }
            }
            .onChange(of: session.finishedTimerStepID) { _, stepID in
                guard let stepID else { return }
                timerAlertStepID = stepID
                session.finishedTimerStepID = nil
            }
            .sensoryFeedback(.success, trigger: timerAlertStepID)
            .fullScreenCover(isPresented: $showFinished) {
                CookingFinishedView(recipe: session.recipe) {
                    showFinished = false
                    onFinish(session.checkedIngredientIDs)
                    dismiss()
                }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            session.cancelAllNotifications()
        }
        .interactiveDismissDisabled()
    }

    private var navigationBar: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Button {
                withAnimation(.snappy) { session.goToPreviousStep() }
            } label: {
                Label("Zurück", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
            }
            .buttonStyle(.bordered)
            .disabled(session.isFirstStep)

            Button {
                if session.isLastStep {
                    showFinished = true
                } else {
                    withAnimation(.snappy) { session.goToNextStep() }
                }
            } label: {
                Label(session.isLastStep ? "Fertig" : "Weiter", systemImage: session.isLastStep ? "checkmark" : "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isLastStep ? AppTheme.trust : AppTheme.accent)
        }
        .font(.headline)
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.vertical, AppTheme.Spacing.m)
        .background(.bar)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: session.currentStepIndex)
    }

    private func leave() {
        session.cancelAllNotifications()
        onFinish(session.checkedIngredientIDs)
        dismiss()
    }
}

/// Eine Schrittseite: großer Text, relevante Zutaten, Timer.
private struct CookingStepPage: View {
    let session: CookingSession
    let step: CookingStep
    let index: Int
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                Text(step.text)
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let temperature = step.temperatureCelsius {
                    Label("\(temperature) °C", systemImage: "thermometer.medium")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                let relevant = session.ingredients(for: step)
                if !relevant.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                        Text("In diesem Schritt")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(relevant, id: \.id) { ingredient in
                            HStack(spacing: AppTheme.Spacing.s) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(AppTheme.accent)
                                Text(QuantityFormatter.string(for: session.scaler.scale(ingredient.measure)))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                Text(ingredient.name)
                            }
                            .font(.title3)
                        }
                    }
                    .padding(AppTheme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
                }

                if step.hasTimer {
                    StepTimerView(session: session, step: step, now: now)
                }
            }
            .padding(AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }
}

/// Timer-Karte: Start/Pause, ±1 Minute, Fortschrittsring.
struct StepTimerView: View {
    let session: CookingSession
    let step: CookingStep
    let now: Date

    private var timer: StepTimer { session.timer(for: step) ?? StepTimer(total: TimeInterval(step.durationSeconds ?? 0)) }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.l) {
            ZStack {
                Circle()
                    .stroke(AppTheme.tertiaryBackground, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: timer.progress(at: now))
                    .stroke(timer.isFinished ? AppTheme.trust : AppTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress(at: now))
                VStack(spacing: 2) {
                    Text(DurationFormatting.clock(Int(timer.remaining(at: now).rounded(.up))))
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                    Text(timer.isFinished ? "Fertig" : (timer.isRunning ? "läuft" : "Timer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timer")
            .accessibilityValue(DurationFormatting.short(Int(timer.remaining(at: now))))

            HStack(spacing: AppTheme.Spacing.m) {
                adjustButton(label: "−1 Min", delta: -60)
                Button {
                    if timer.isRunning {
                        session.pauseTimer(for: step, now: now)
                    } else {
                        session.startTimer(for: step, now: now)
                    }
                } label: {
                    Label(timer.isRunning ? "Pause" : (timer.isIdle ? "Starten" : "Weiter"), systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .frame(minWidth: 120, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(timer.isFinished ? AppTheme.trust : AppTheme.accent)
                adjustButton(label: "+1 Min", delta: 60)
            }
            .font(.headline)

            if !timer.isIdle {
                Button("Zurücksetzen") { session.resetTimer(for: step) }
                    .font(.subheadline)
            }
        }
        .padding(AppTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func adjustButton(label: String, delta: TimeInterval) -> some View {
        Button(label) { session.adjustTimer(for: step, by: delta, now: now) }
            .buttonStyle(.bordered)
            .frame(minHeight: 50)
            .disabled(timer.isFinished)
    }
}

/// Zutaten-Checkliste als Sheet im Koch-Modus (Mengen skaliert).
private struct CookingIngredientsSheet: View {
    @Bindable var session: CookingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(session.recipe.ingredientGroups.enumerated()), id: \.offset) { _, group in
                    Section(group.title ?? "") {
                        ForEach(group.items, id: \.id) { ingredient in
                            IngredientRowView(
                                ingredient: ingredient,
                                scaler: session.scaler,
                                isChecked: session.checkedIngredientIDs.contains(ingredient.id)
                            ) {
                                withAnimation(.snappy) { session.toggleIngredient(ingredient) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Zutaten · \(session.scaler.targetServings) Portionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}

/// Abschluss-Screen mit Mint-Erfolgsmeldung.
private struct CookingFinishedView: View {
    let recipe: Recipe
    let onDone: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 88))
                .foregroundStyle(AppTheme.trust)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("Guten Appetit!")
                .font(.largeTitle.weight(.bold))
            Text("„\(recipe.title)“ wurde als gekocht markiert.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onDone) {
                Text("Zur Bibliothek")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.trust)
        }
        .padding(AppTheme.Spacing.xl)
        .background(AppTheme.background)
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared)
    }
}

/// Label mit Icon rechts ("Weiter ›").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    CookingModeView(
        session: CookingSession(recipe: Recipe.sampleShakshuka(), scaler: ServingsScaler(baseServings: 2, targetServings: 4)),
        onFinish: { _ in }
    )
    .modelContainer(RecipeSchemaV1.previewContainer())
}
