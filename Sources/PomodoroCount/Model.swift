import Foundation
import AppKit

// MARK: - App model

/// The half-second heartbeat of a running session, kept apart from `AppModel`
/// on purpose. Every view in the panel observes the model, so anything
/// `@Published` there re-renders all of them — and `remaining` changes twice a
/// second for the whole length of every session. Only two views actually
/// display seconds (the big countdown and the menu bar item); they observe
/// this clock directly, and everything else now re-renders only when
/// something it shows has changed.
@MainActor
final class SessionClock: ObservableObject {
    @Published fileprivate(set) var remaining: TimeInterval = 0
}

@MainActor
final class AppModel: ObservableObject {
    /// Shared instance used by the running app (so the AppDelegate and the
    /// global hotkey can reach the same model the UI observes).
    static let shared = AppModel()

    /// Set once at startup (via `--store`) to redirect persistence for testing.
    nonisolated(unsafe) static var overrideStoreURL: URL?

    @Published var records: [Record] = [] { didSet { save() } }
    @Published var settings = Settings() { didSet { save() } }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRunning = false

    /// See `SessionClock` — the countdown lives there so its tick doesn't
    /// invalidate the whole panel. Everything phase-shaped stays here: phase
    /// and isRunning change a handful of times a session, not twice a second.
    let clock = SessionClock()
    var remaining: TimeInterval { clock.remaining }

    /// Which category a finished focus session credits. Persisted so it survives
    /// relaunch — re-picking it every day would be a papercut.
    var sessionTarget: CategoryTarget {
        get {
            guard let name = settings.sessionTargetName, categoryExists(name) else {
                return .fallback
            }
            return .named(name)
        }
        set { settings.aim(at: newValue) }
    }

    /// What the panel's "towards …" line says a finished session will credit.
    ///
    /// Derived from `resolve`, not from the target's shape, so it cannot promise
    /// one destination while the record goes to another — which is exactly what
    /// happened when it read an unset target as "the bucket" on its own.
    var sessionTargetLabel: String {
        resolve(sessionTarget) ?? settings.fallbackName
    }

    /// What the target text says, and what VoiceOver reads.
    ///
    /// Two different promises rather than a mode indicator: `towards …` means
    /// the ranking is driving and will move on when that category is done,
    /// `pinned to …` means the user asked to keep going past a goal already met.
    /// Wording them differently is the whole visible difference between the two
    /// kinds of hand pick, so it carries real information rather than decorating
    /// a state.
    ///
    /// With `autoAdvanceTarget` off there is no automatic behaviour for a pin to
    /// hold out against, so the distinction stops being worth showing and
    /// everything reads `towards …`. The flag stays recorded, so turning the
    /// rule back on restores whatever was already being promised.
    var sessionTargetDescription: String {
        sessionTargetPromise + sessionTargetLabel
    }

    /// Which of the two promises is in force, trailing space included so it
    /// composes with a name.
    private var sessionTargetPromise: String {
        settings.targetPinned && settings.autoAdvanceTarget ? "pinned to " : "towards "
    }

    /// Drives the timer to completion immediately. Used by tests, and by
    /// `PreviewRenderer` under `--preview --armed-break` — both need a
    /// finished session without sitting out the real 50 minutes.
    func forceCompleteForTesting() {
        clock.remaining = 0
        complete()
    }

    private var endDate: Date?
    private var timer: Timer?
    var nudgeTimer: Timer?
    var hotKey: HotKeyManager?
    var dayChangeObserver: NSObjectProtocol?
    var screenLockObserver: NSObjectProtocol?
    var clockChangeObserver: NSObjectProtocol?
    /// The calendar day the model last saw, so a day change can be told apart
    /// from a wake. `didWakeNotification` fires on every wake — a five-minute
    /// lid-close in the middle of a break included — and running the rollover
    /// off that unguarded would eat the break.
    ///
    /// In memory, not persisted, matching `focusSessionsThisCycle`: `phase`
    /// isn't persisted either, so a relaunch already lands on `.idle` with a
    /// fresh cycle. This only has to be right for a process that stays up.
    var lastSeenDay = Calendar.current.startOfDay(for: Date())
    let customStoreURL: URL?
    var isLoading = false

    /// How many bursts of related changes are in flight, so they cost one store
    /// write between them instead of one each. Bursts nest, so this counts
    /// rather than flags — see `suspendSaves()`.
    var suspendDepth = 0
    /// Suspended while any burst is still in flight.
    var savesSuspended: Bool { suspendDepth > 0 }
    /// A save asked for while suspended, to be honoured on resume.
    var savePending = false

    /// `storeURL` overrides the on-disk location (used by tests so they never
    /// touch the user's real data). Defaults to Application Support.
    init(storeURL: URL? = nil) {
        self.customStoreURL = storeURL ?? Self.overrideStoreURL
        // Checked before load(), which creates the containing directory.
        isFirstLaunch = !FileManager.default.fileExists(atPath: self.storeURL.path)
        load()
    }

    /// True when no data file exists yet, i.e. a brand-new install. Used once, to
    /// open the panel so launching the app does something visible.
    private(set) var isFirstLaunch = false

    /// Writes the store even though nothing has changed, so the next launch is
    /// not also a first launch. Without this the welcome would repeat until the
    /// user happened to log a pomodoro or change a setting.
    func markLaunched() {
        isFirstLaunch = false
        save()
    }

    // MARK: Derived values

    var todayCount: Int {
        records.filter { Calendar.current.isDateInToday($0.at) }.count
    }

    var weekCount: Int {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) else { return 0 }
        return records.filter { $0.at >= start }.count
    }

    var totalCount: Int { records.count }

    /// Time shown on the big timer. Neither stopped phase has a countdown, so
    /// each previews the length of whatever its primary button will start —
    /// computed from settings rather than stored, so editing a length in
    /// Settings moves the readout while it is on screen.
    var displayRemaining: TimeInterval {
        switch phase {
        case .idle:             return TimeInterval(settings.workMinutes * 60)
        case .breakReady:       return TimeInterval(armedBreakMinutes * 60)
        case .work, .breakTime: return remaining
        }
    }

    var primaryTitle: String {
        if isRunning { return "Pause" }
        switch phase {
        case .idle:             return "Start focus"
        case .breakReady:       return "Start break"
        case .work, .breakTime: return "Resume"
        }
    }

    /// Whether the panel offers the "rest now" cup button. Not while a break is
    /// already armed — the primary button offers exactly that, and two controls
    /// doing one job in one row is worse than one.
    var offersManualBreak: Bool {
        phase == .idle || phase == .work
    }

    /// The stop button's tooltip. It abandons an unfinished session in the
    /// running phases, but an armed break has a session already logged behind
    /// it, so "nothing is logged" would be a lie exactly where the user is most
    /// likely to hesitate over the button.
    var resetHelp: String {
        phase == .breakReady
            ? "Skip the break — the session is already logged"
            : "Abandons the session — nothing is logged"
    }

    /// Whether the stop button does anything. True whenever there is a session
    /// or an armed break to walk away from. `.breakReady` counts: it has no
    /// countdown running, but the session behind it is already logged, and the
    /// button is how you skip the break instead of taking it — disabling it
    /// there would leave that armed break with no way to decline.
    var offersReset: Bool {
        phase != .idle
    }

    /// The first instant of an N-day window ending today. Every "last N days"
    /// query — `history`, `dailySeries`, `categoryTotals` — measures its window
    /// from here, so the semantics (inclusive of today, calendar-day aligned)
    /// can only be changed in one place. Force-unwrapped because day
    /// arithmetic on a real calendar cannot fail for the small positive `days`
    /// these queries pass.
    func windowStart(days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))!
    }

    /// Days within the last `days` days (ending today) that have at least one
    /// record, newest first. Powers the History tab's day list, so the
    /// Week/Month control governs it the same way it governs `dailySeries` and
    /// `categoryTotals`. Unlike `dailySeries`, empty days are not padded in —
    /// the day list has always shown only days you actually logged something.
    func history(days: Int) -> [DayStat] {
        let cal = Calendar.current
        let cutoff = windowStart(days: days, calendar: cal)
        let groups = Dictionary(grouping: records.filter { $0.at >= cutoff }) { cal.startOfDay(for: $0.at) }
        return groups
            .map { DayStat(date: $0.key, count: $0.value.count) }
            .sorted { $0.date > $1.date }
    }

    /// Consecutive days with at least one pomodoro, ending today — or ending
    /// yesterday, because a streak must not read as broken at midnight before
    /// today's first pomodoro has had a chance to happen. One pass to bucket
    /// the days, then a walk backwards.
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.at) })
        guard !days.isEmpty else { return 0 }

        var cursor = cal.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Text shown next to the icon in the menu bar (count when idle or armed,
    /// else clock). Empty means icon-only — see `Settings.showsCountInMenuBar`.
    /// That hides the count visually only: `statusDescription` still speaks it
    /// to VoiceOver in every phase, drawn or not.
    var statusText: String {
        switch phase {
        // An armed break has no countdown, so the item keeps showing the count
        // and the cup glyph carries the news that a break is waiting.
        case .idle, .breakReady: return settings.showsCountInMenuBar ? "\(todayCount)" : ""
        case .work, .breakTime:  return Self.mmss(remaining)
        }
    }

    /// The full menu bar item: custom icon + text, rendered as one template image.
    var statusImage: NSImage {
        StatusIcon.render(phase: phase, running: isRunning, text: statusText,
                          description: statusDescription)
    }

    /// What VoiceOver announces for the menu bar item.
    var statusDescription: String {
        switch phase {
        case .idle:
            return "Pomodoro Count: \(todayCount) \(todayCount == 1 ? "pomodoro" : "pomodoros") today"
        case .breakReady:
            return "Break ready: \(Self.spokenDuration(TimeInterval(armedBreakMinutes * 60))); "
                 + "\(todayCount) \(todayCount == 1 ? "pomodoro" : "pomodoros") today"
        case .work:
            return "Focus\(isRunning ? "" : ", paused"): \(Self.spokenDuration(remaining)) remaining"
        case .breakTime:
            return "Break\(isRunning ? "" : ", paused"): \(Self.spokenDuration(remaining)) remaining"
        }
    }

    /// Exactly `days` consecutive days ending today, zero-filled, oldest first —
    /// for the weekly / monthly bar chart and the header sparkline.
    ///
    /// Filters to the window with a cheap date comparison before doing any
    /// per-record calendar work, like `history` and `categoryTotals`. It used
    /// to bucket the entire history by `startOfDay` to read out `days` values —
    /// and the sparkline sits on the Focus tab, re-rendered on every 0.5s tick
    /// of a running session, so that cost was paid twice a second and grew
    /// with the age of the store.
    func dailySeries(days: Int) -> [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = windowStart(days: days, calendar: cal)
        let counts = Dictionary(grouping: records.filter { $0.at >= cutoff }) { cal.startOfDay(for: $0.at) }
            .mapValues { $0.count }
        return (0..<days).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayStat(date: d, count: counts[d] ?? 0)
        }
    }

    // MARK: Timer control

    func toggle() {
        if isRunning {
            pause()
        } else if phase == .idle {
            startWork()
        } else if phase == .breakReady {
            // Not `resume()`. There is no countdown behind an armed break, and
            // `resume()`'s guard only excludes `.idle` — it would happily start
            // ticking from a stale `remaining`, which is zero straight after
            // the focus session that armed this.
            startBreak()
        } else {
            resume()
        }
    }

    func startWork() {
        phase = .work
        clock.remaining = TimeInterval(settings.workMinutes * 60)
        beginCountdown()
    }

    /// Completed focus sessions since the last long break. In memory only: a
    /// relaunch restarts the cycle, which is the least surprising thing a
    /// counter nobody can see can do. Abandoned sessions don't count — only
    /// `complete()` advances it.
    private(set) var focusSessionsThisCycle = 0

    /// True while the running break is the long one, so the UI can say so.
    private(set) var currentBreakIsLong = false

    /// When the current break phase began — armed by `complete()` or started by
    /// `startBreak()`. nil whenever the timer is not on a break.
    ///
    /// Read by `handleDayChange` to tell a break left over from yesterday from
    /// one earned this morning. See `DayRollover.action` for why the two are
    /// not distinguishable from the day stamp alone.
    var breakEnteredOn: Date?

    /// The classic rhythm: every fourth completed focus session earns the
    /// long break. `>=` rather than `==` so declining the fourth break (auto-
    /// start off, straight into a fifth session) keeps the long break owed
    /// rather than skipping it.
    var nextBreakIsLong: Bool { focusSessionsThisCycle >= 4 }

    /// How long the break offered right now will run for. One source of truth:
    /// the armed state previews this number and `startBreak()` counts down from
    /// it, so what the panel promises and what runs cannot diverge.
    var armedBreakMinutes: Int {
        nextBreakIsLong ? settings.longBreakMinutes : settings.breakMinutes
    }

    func startBreak() {
        let long = nextBreakIsLong
        // Read before the cycle resets: `armedBreakMinutes` is derived from
        // `focusSessionsThisCycle`, so asking after the reset below would
        // always answer "short".
        let minutes = armedBreakMinutes
        if long { focusSessionsThisCycle = 0 }   // taking it restarts the cycle
        currentBreakIsLong = long
        phase = .breakTime
        breakEnteredOn = Date()
        clock.remaining = TimeInterval(minutes * 60)
        beginCountdown()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        stopTimer()
        if let endDate { clock.remaining = max(0, endDate.timeIntervalSinceNow) }
        endDate = nil
    }

    func resume() {
        // `.breakReady` is stopped but has no countdown behind it — resuming
        // would tick from a stale `remaining` of zero and "complete" a break
        // that never ran. `toggle()` routes that phase to `startBreak()`; this
        // guard makes that the only way in.
        guard !isRunning, phase == .work || phase == .breakTime else { return }
        beginCountdown()
    }

    func reset() {
        stopTimer()
        isRunning = false
        phase = .idle
        endDate = nil
        clock.remaining = 0
        breakEnteredOn = nil
    }

    /// Starts the day's rhythm over: the timer back to idle and the long-break
    /// cycle back to zero, so a new day doesn't open owing yesterday's long
    /// break.
    ///
    /// Lives here rather than next to `handleDayChange` because
    /// `focusSessionsThisCycle` is `private(set)`, and Swift scopes that to
    /// the file.
    func resetForNewDay() {
        reset()
        focusSessionsThisCycle = 0
    }

    private func beginCountdown() {
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        stopTimer()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let endDate else { return }
        clock.remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            clock.remaining = 0
            complete()
        }
    }

    /// The body of the banner a finished focus session posts. Extracted and
    /// pure because `notify` returns early unless the app is bundled, so this
    /// wording posts nothing under test — and with auto-start off it is the
    /// only news a user with the panel closed gets.
    static func completionBody(count: Int, breakArmed: Bool) -> String {
        breakArmed
            ? "That's \(count) today — break's ready when you are."
            : "Nice — that's \(count) today."
    }

    private func complete() {
        stopTimer()
        isRunning = false
        let finished = phase
        endDate = nil

        if finished == .work {
            focusSessionsThisCycle += 1
            // The record and the target it may have just moved are one change
            // as far as the store is concerned, so they cost one write rather
            // than two. The append comes first: this session credits the target
            // it actually ran against, and only the next one moves.
            suspendSaves()
            records.append(Record(at: Date(), source: "timer",
                                  category: resolve(sessionTarget)))
            realignTarget()
            resumeSaves()
            play(.sessionDone)
            notify("Pomodoro complete",
                   Self.completionBody(count: todayCount,
                                       breakArmed: !settings.autoStartBreak))
            if settings.autoStartBreak {
                startBreak()
            } else {
                // Not `.idle`: the break is owed, so offer it at the length it
                // will run for instead of dropping back to previewing focus.
                phase = .breakReady
                breakEnteredOn = Date()
            }
        } else {
            play(.breakOver)
            notify("Break over", "Ready for the next one?")
            phase = .idle
            // The break is over, so the stamp that said when it began must go
            // with it — `breakEnteredOn` promises nil off a break, and a stale
            // value here would outlive the phase that justified it.
            breakEnteredOn = nil
        }
    }

    // MARK: External / manual logging (the headline feature)

    /// Records a pomodoro completed outside the app, e.g. on a physical timer.
    /// `announce` (used by the global hotkey) also posts a confirmation banner,
    /// since the panel may not be open to show the count change.
    func logExternal(to target: CategoryTarget = .fallback, announce: Bool = false) {
        // One write for the pair, as in `complete()`. `target` is usually not the
        // session target — the log button and the hotkey both pass `.fallback`,
        // a category row passes its own name — but the advance asks about the
        // session target either way: what matters is whether the category the
        // timer will credit is finished.
        suspendSaves()
        records.append(Record(at: Date(), source: "manual", category: resolve(target)))
        realignTarget()
        resumeSaves()
        play(.countUp)
        if announce {
            notify("Pomodoro logged", "That's \(todayCount) today.")
        }
    }

    /// Removes the most recently added record (undo a mis-tap).
    func undoLast() {
        guard let idx = records.indices.max(by: { records[$0].at < records[$1].at }) else { return }
        records.remove(at: idx)
        play(.countDown)
    }

    /// Removes today's most recent record in one category — the subtract half of
    /// the category row's counter. A category with nothing logged today is a
    /// no-op, so a count can never go negative; the popover disables its `−`
    /// there too, but the model must not depend on a view for that.
    ///
    /// Deliberately does **not** call `realignTarget()`, unlike every appending
    /// path. The advance is forward-only on purpose: re-aiming because a count
    /// dropped would move the target out from under a Start the user has already
    /// pressed, and it would undo a hand-picked pin the moment a mis-tap was
    /// corrected. `undoLast()` has left the target alone for the same reason
    /// since it was written. `unlogTodayLeavesTheSessionTargetAlone` fails if
    /// this gets "fixed" for symmetry.
    ///
    /// No `suspendSaves()` bracket either: that exists for a *burst* of related
    /// changes, and this is one mutation of `records`, whose `didSet` should
    /// write exactly once. `logExternal` brackets because it pairs an append
    /// with a target advance; a removal has no second half to pair with.
    func unlogToday(from target: CategoryTarget) {
        guard let index = CountAdjust.newestTodayIndex(in: records,
                                                      category: resolve(target))
        else { return }
        records.remove(at: index)
        play(.countDown)
    }

}
