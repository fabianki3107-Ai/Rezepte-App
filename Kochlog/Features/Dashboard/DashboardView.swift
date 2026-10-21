import SwiftUI
import SwiftData
import Charts

/// Tagesübersicht: Kalorienring, Makro-Balken, Wochenverlauf und die heute geloggten Rezepte.
struct DashboardView: View {
    @Environment(NutritionLogService.self) private var nutritionLog
    @State private var settings = AppSettings.shared
    @State private var selectedDate = Date()
    @State private var editingEntry: LogEntry?

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.l) {
                    DayLogContent(date: selectedDate, goals: settings.goals, onEdit: { editingEntry = $0 })
                    WeeklyCaloriesChart(endDate: selectedDate, goal: settings.goals.calories)
                }
                .padding(.horizontal, AppTheme.Spacing.l)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .background(AppTheme.background)
            .navigationTitle(isToday ? "Heute" : selectedDate.formatted(.dateTime.weekday(.wide).day().month()))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        shiftDay(-1)
                    } label: {
                        Label("Vortag", systemImage: "chevron.left")
                    }
                    Button {
                        shiftDay(1)
                    } label: {
                        Label("Nächster Tag", systemImage: "chevron.right")
                    }
                    .disabled(isToday)
                    if !isToday {
                        Button("Heute") { withAnimation { selectedDate = .now } }
                    }
                }
            }
            .sheet(item: $editingEntry) { entry in
                ServingsEditorSheet(entry: entry)
                    .presentationDetents([.medium])
            }
        }
    }

    private func shiftDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        withAnimation(.snappy) { selectedDate = min(next, .now) }
    }
}

/// Lädt den `DailyLog` eines Tages per `@Query` – eigene View, damit das Prädikat dynamisch gesetzt werden kann.
private struct DayLogContent: View {
    @Environment(NutritionLogService.self) private var nutritionLog
    @Query private var logs: [DailyLog]
    private let goals: NutritionGoals
    private let onEdit: (LogEntry) -> Void

    init(date: Date, goals: NutritionGoals, onEdit: @escaping (LogEntry) -> Void) {
        let day = Calendar.current.startOfDay(for: date)
        _logs = Query(filter: #Predicate<DailyLog> { $0.dayStart == day })
        self.goals = goals
        self.onEdit = onEdit
    }

    private var totals: NutritionFacts { logs.first?.totals ?? .zero }
    private var entries: [LogEntry] { logs.first?.sortedEntries ?? [] }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.l) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.l) {
                CalorieRingView(consumed: totals.calories, goal: Double(goals.calories))
                    .frame(width: 150, height: 150)
                MacroBarsView(totals: totals, goals: goals)
            }
            .padding(AppTheme.Spacing.l)
            .cardBackground()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                HStack {
                    Text("Gegessen")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if !entries.isEmpty {
                        Text("\(entries.count) \(entries.count == 1 ? "Eintrag" : "Einträge")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Noch nichts geloggt", systemImage: "fork.knife.circle")
                    } description: {
                        Text("Öffne ein Rezept und tippe auf „Heute loggen“ – die Nährwerte landen sofort hier.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.m)
                    .cardBackground()
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries, id: \.id) { entry in
                            LogEntryRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture { onEdit(entry) }
                                .contextMenu {
                                    Button("Portionen ändern", systemImage: "slider.horizontal.3") { onEdit(entry) }
                                    Button("Löschen", systemImage: "trash", role: .destructive) {
                                        try? nutritionLog.remove(entry)
                                    }
                                }
                            if entry.id != entries.last?.id {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.l)
                    .padding(.vertical, AppTheme.Spacing.s)
                    .cardBackground()
                }
            }
        }
    }
}

/// Kalorienring im Stil der Fitness-App – nativ mit Swift Charts (`SectorMark`).
struct CalorieRingView: View {
    let consumed: Double
    let goal: Double

    private var remaining: Double { max(0, goal - consumed) }
    private var isOverGoal: Bool { consumed > goal && goal > 0 }
    private var ringColor: Color { isOverGoal ? AppTheme.warning : AppTheme.accent }

    var body: some View {
        Chart {
            SectorMark(angle: .value("Gegessen", min(consumed, goal)), innerRadius: .ratio(0.78), angularInset: 1)
                .foregroundStyle(ringColor)
                .cornerRadius(8)
            if remaining > 0 {
                SectorMark(angle: .value("Offen", remaining), innerRadius: .ratio(0.78), angularInset: 1)
                    .foregroundStyle(AppTheme.tertiaryBackground)
                    .cornerRadius(8)
            }
        }
        .chartLegend(.hidden)
        .animation(.snappy, value: consumed)
        .overlay {
            VStack(spacing: 2) {
                Text(Int(consumed.rounded()).formatted())
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(isOverGoal ? "+\(Int((consumed - goal).rounded())) über Ziel" : "von \(Int(goal)) kcal")
                    .font(.caption)
                    .foregroundStyle(isOverGoal ? AppTheme.warning : .secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kalorien")
        .accessibilityValue("\(Int(consumed)) von \(Int(goal)) Kilokalorien")
    }
}

/// Drei Makro-Balken mit nativer `ProgressView`.
struct MacroBarsView: View {
    let totals: NutritionFacts
    let goals: NutritionGoals

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            ForEach(Macro.allCases) { macro in
                let value = totals.value(for: macro)
                let goal = Double(goals.goal(for: macro))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(macro.shortTitle, systemImage: macro.symbolName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(macro.color)
                        Spacer()
                        Text("\(Int(value.rounded())) / \(Int(goal)) g")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    ProgressView(value: min(value, goal), total: max(goal, 1))
                        .tint(macro.color)
                        .animation(.snappy, value: value)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(macro.title)
                .accessibilityValue("\(Int(value)) von \(Int(goal)) Gramm")
            }
        }
    }
}

extension Macro {
    /// Unterscheidbare Systemfarben; Blau bleibt Interaktionen, Mint den Erfolgen vorbehalten.
    var color: Color {
        switch self {
        case .protein: return Color(uiColor: .systemIndigo)
        case .carbs: return Color(uiColor: .systemOrange)
        case .fat: return Color(uiColor: .systemTeal)
        }
    }
}

/// Balken der letzten sieben Tage mit Ziel-Linie.
struct WeeklyCaloriesChart: View {
    @Environment(NutritionLogService.self) private var nutritionLog
    @Query(sort: \DailyLog.dayStart) private var allLogs: [DailyLog]
    let endDate: Date
    let goal: Int

    private struct DayPoint: Identifiable {
        let day: Date
        let calories: Int
        var id: Date { day }
    }

    private var points: [DayPoint] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { return nil }
            let calories = allLogs.first { calendar.isDate($0.dayStart, inSameDayAs: day) }?.totalCalories ?? 0
            return DayPoint(day: day, calories: calories)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Text("Letzte 7 Tage")
                .font(.title3.weight(.semibold))
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Tag", point.day, unit: .day), y: .value("kcal", point.calories))
                        .foregroundStyle(Calendar.current.isDate(point.day, inSameDayAs: endDate) ? AppTheme.accent : AppTheme.accent.opacity(0.35))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Ziel", goal))
                    .foregroundStyle(AppTheme.trust)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Ziel \(goal)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.trust)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 160)
            .padding(AppTheme.Spacing.l)
            .cardBackground()
            .accessibilityLabel("Kalorien der letzten sieben Tage")
        }
    }
}

/// Zeile eines Tagebuch-Eintrags.
struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: entry.meal.symbolName)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40, height: 40)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(entry.loggedAt, style: .time)
                    Text("·")
                    Text(ServingsFormatting.string(entry.servings))
                    if entry.healthKitState == .synced {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(AppTheme.trust)
                            .accessibilityLabel("In Apple Health")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.calories) kcal")
                    .font(.body.weight(.semibold).monospacedDigit())
                Text("E \(Int(entry.protein.rounded())) · K \(Int(entry.carbs.rounded())) · F \(Int(entry.fat.rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// Portionen und Mahlzeit eines Eintrags nachträglich anpassen.
struct ServingsEditorSheet: View {
    @Environment(NutritionLogService.self) private var nutritionLog
    @Environment(\.dismiss) private var dismiss
    let entry: LogEntry
    @State private var servings: Double = 1
    @State private var meal: MealSlot = .snack

    var body: some View {
        NavigationStack {
            Form {
                Section("Portionen") {
                    Stepper(value: $servings, in: 0.25...10, step: 0.25) {
                        LabeledContent("Menge", value: ServingsFormatting.string(servings))
                    }
                    if let perServing = entry.recipe?.nutrition {
                        LabeledContent("Ergibt", value: "\(Int(perServing.scaled(by: servings).calories.rounded())) kcal")
                    }
                }
                Section("Mahlzeit") {
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(MealSlot.allCases) { slot in
                            Label(slot.title, systemImage: slot.symbolName).tag(slot)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button("Eintrag löschen", role: .destructive) {
                        try? nutritionLog.remove(entry)
                        dismiss()
                    }
                }
            }
            .navigationTitle(entry.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        try? nutritionLog.updateServings(entry, servings: servings)
                        try? nutritionLog.updateMeal(entry, meal: meal)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                servings = entry.servings
                meal = entry.meal
            }
        }
    }
}

enum ServingsFormatting {
    /// "1 Portion", "1,5 Portionen", "½ Portion".
    static func string(_ servings: Double) -> String {
        let amount = QuantityFormatter.number(servings, unit: .piece)
        return servings <= 1 ? "\(amount) Portion" : "\(amount) Portionen"
    }
}

#Preview {
    DashboardView()
        .environment(NutritionLogService.preview)
        .modelContainer(RecipeSchemaV1.previewContainer())
}
