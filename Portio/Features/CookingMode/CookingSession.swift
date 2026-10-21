import Foundation
import Observation

/// Zustand einer Koch-Sitzung: aktueller Schritt, abgehakte Zutaten, Timer pro Schritt.
/// Rein in-memory – eine Sitzung ist flüchtig und muss den Store nicht berühren.
@MainActor
@Observable
final class CookingSession {
    let recipe: RecipeItem
    let scaler: ServingsScaler
    let steps: [CookingStep]

    var currentStepIndex = 0
    var checkedIngredientIDs: Set<UUID>
    private(set) var timers: [UUID: StepTimer] = [:]
    /// Wird gesetzt, sobald ein Timer abläuft; die View reagiert mit Haptik/Ton und setzt zurück.
    var finishedTimerStepID: UUID?

    private let notifications: TimerNotificationService
    private let settings: AppSettings

    init(
        recipe: RecipeItem,
        scaler: ServingsScaler,
        checkedIngredientIDs: Set<UUID> = [],
        notifications: TimerNotificationService = .shared,
        settings: AppSettings = .shared
    ) {
        self.recipe = recipe
        self.scaler = scaler
        self.steps = recipe.sortedSteps
        self.checkedIngredientIDs = checkedIngredientIDs
        self.notifications = notifications
        self.settings = settings
    }

    // MARK: Navigation

    var currentStep: CookingStep? { steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil }
    var isFirstStep: Bool { currentStepIndex == 0 }
    var isLastStep: Bool { currentStepIndex >= steps.count - 1 }
    var progress: Double { steps.isEmpty ? 0 : Double(currentStepIndex + 1) / Double(steps.count) }

    func goToNextStep() {
        guard !isLastStep else { return }
        currentStepIndex += 1
    }

    func goToPreviousStep() {
        guard !isFirstStep else { return }
        currentStepIndex -= 1
    }

    // MARK: Zutaten

    func toggleIngredient(_ ingredient: Ingredient) {
        if checkedIngredientIDs.contains(ingredient.id) {
            checkedIngredientIDs.remove(ingredient.id)
        } else {
            checkedIngredientIDs.insert(ingredient.id)
        }
    }

    /// Zutaten, deren Name im Schritt-Text vorkommt (Wortstamm-Abgleich ≥ 4 Zeichen).
    func ingredients(for step: CookingStep) -> [Ingredient] {
        let haystack = step.text.lowercased()
        return recipe.sortedIngredients.filter { ingredient in
            ingredient.name
                .lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .filter { $0.count >= 4 }
                .contains { word in
                    // "Zwiebeln" ↔ "Zwiebel": Stamm der ersten 5 Zeichen vergleichen
                    let stem = String(word.prefix(max(4, word.count - 2)))
                    return haystack.contains(stem)
                }
        }
    }

    // MARK: Timer

    func timer(for step: CookingStep) -> StepTimer? { timers[step.id] }

    func startTimer(for step: CookingStep, now: Date = .now) {
        guard let duration = step.durationSeconds, duration > 0 else { return }
        var timer = timers[step.id] ?? StepTimer(total: TimeInterval(duration))
        timer.start(now: now)
        timers[step.id] = timer
        scheduleNotification(for: step, timer: timer)
    }

    func pauseTimer(for step: CookingStep, now: Date = .now) {
        guard var timer = timers[step.id] else { return }
        timer.pause(now: now)
        timers[step.id] = timer
        notifications.cancel(id: notificationID(for: step))
    }

    func resetTimer(for step: CookingStep) {
        timers[step.id] = nil
        notifications.cancel(id: notificationID(for: step))
    }

    func adjustTimer(for step: CookingStep, by delta: TimeInterval, now: Date = .now) {
        guard var timer = timers[step.id] else { return }
        timer.adjust(by: delta, now: now)
        timers[step.id] = timer
        if timer.isRunning { scheduleNotification(for: step, timer: timer) }
    }

    /// Von der View im Sekundentakt aufgerufen (TimelineView); erkennt abgelaufene Timer.
    func tick(now: Date) {
        for (stepID, timer) in timers where timer.isRunning && timer.remaining(at: now) <= 0 {
            var finished = timer
            finished.markFinished()
            timers[stepID] = finished
            finishedTimerStepID = stepID
        }
    }

    var hasRunningTimer: Bool { timers.values.contains { $0.isRunning } }

    private func scheduleNotification(for step: CookingStep, timer: StepTimer) {
        guard settings.timerNotifications else { return }
        let id = notificationID(for: step)
        let remaining = timer.remaining(at: .now)
        let title = recipe.title
        let stepNumber = (steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1
        Task {
            guard await notifications.requestAuthorizationIfNeeded() else { return }
            notifications.cancel(id: id)
            await notifications.schedule(
                id: id,
                title: "Timer abgelaufen",
                body: "\(title) – Schritt \(stepNumber) ist fertig.",
                fireIn: remaining
            )
        }
    }

    private func notificationID(for step: CookingStep) -> String { "timer.\(step.id.uuidString)" }

    func cancelAllNotifications() {
        for step in steps { notifications.cancel(id: notificationID(for: step)) }
    }
}

/// Timer-Zustand als Werttyp. Rechnet mit Enddaten statt zu zählen,
/// damit er Hintergrundphasen und UI-Pausen überlebt.
struct StepTimer: Hashable {
    enum State: Hashable { case idle, running(endDate: Date), paused(remaining: TimeInterval), finished }

    var total: TimeInterval
    var state: State = .idle

    var isRunning: Bool { if case .running = state { return true } else { return false } }
    var isFinished: Bool { state == .finished }
    var isIdle: Bool { state == .idle }

    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle: return total
        case .running(let endDate): return max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): return remaining
        case .finished: return 0
        }
    }

    func progress(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return 1 - remaining(at: now) / total
    }

    mutating func start(now: Date) {
        switch state {
        case .idle, .finished: state = .running(endDate: now.addingTimeInterval(total))
        case .paused(let remaining): state = .running(endDate: now.addingTimeInterval(remaining))
        case .running: break
        }
    }

    mutating func pause(now: Date) {
        if case .running = state { state = .paused(remaining: remaining(at: now)) }
    }

    mutating func adjust(by delta: TimeInterval, now: Date) {
        switch state {
        case .running(let endDate): state = .running(endDate: max(now, endDate.addingTimeInterval(delta)))
        case .paused(let remaining): state = .paused(remaining: max(0, remaining + delta))
        case .idle: total = max(1, total + delta)
        case .finished: break
        }
    }

    mutating func markFinished() { state = .finished }
}
