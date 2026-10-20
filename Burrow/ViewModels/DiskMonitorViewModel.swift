import AppKit
import Foundation
import SwiftUI // ObservableObject + @Published only
import os

/// Backs the Monitoring tab. While enabled it checks the configured volumes
/// on a timer, raises a macOS notification when one drops to or below the
/// threshold, and — if the user filled in Slack — posts a report to their
/// channel. Owned by `AppDelegate`, so it runs whether or not a window is
/// open. Report logic lives in `DiskMonitorReport`, delivery in
/// `SlackClient` / `DiskMonitorNotifier`; I/O is injected for tests.
@MainActor
final class DiskMonitorViewModel: ObservableObject {

    /// Side effects, swappable in tests.
    struct Dependencies {
        var readAll: ([String]) async -> [DiskMonitorReport.Reading] = { await DiskMonitorReport.readAll($0) }
        var scanTopFolders: () async -> DiskMonitorReport.TopFolders? = { await DiskMonitorReport.scanTopFolders() }
        var post: (SlackClient.Message, _ token: String, _ channel: String) async throws -> Void = { message, token, channel in
            try await SlackClient(token: token).post(message, to: channel)
        }
        /// Asks for notification permission (may show the system prompt);
        /// true when banners may be shown.
        var authorize: () async -> Bool = { await DiskMonitorNotifier.authorize() }
        /// Reads, without prompting, whether the user turned notifications off.
        var notificationsDenied: () async -> Bool = { await DiskMonitorNotifier.isDenied() }
        var now: () -> Date = { Date() }
        /// Shows the low-disk notification; true when it was delivered.
        var notify: ([DiskMonitorReport.Reading], Double) async -> Bool = { await DiskMonitorNotifier.notify($0, threshold: $1) }
    }

    private let logger = Logger(subsystem: "fun.burrow", category: "DiskMonitorViewModel")
    private let defaults: UserDefaults
    private let keychain: Keychain
    private let deps: Dependencies
    private let recheckDelay: UInt64
    /// Longest single sleep of the timer. It waits for `nextCheck` by wall
    /// clock in slices, since `Task.sleep`'s clock stops while the Mac sleeps.
    private let timerSlice: TimeInterval
    private static let tokenAccount = "bot-token"
    /// How long a top-folder list is reused while a disk stays low, so each
    /// check doesn't walk the whole home folder again.
    private static let topFoldersMaxAge: TimeInterval = 3600

    @Published var settings: DiskMonitorSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            if settings.enabled != oldValue.enabled || settings.intervalMinutes != oldValue.intervalMinutes
                || settings.schedule != oldValue.schedule || settings.dailyMinute != oldValue.dailyMinute {
                reschedule()
            } else if settings.enabled, settings.schedule == .interval,
                      settings.thresholdPercent != oldValue.thresholdPercent || settings.paths != oldValue.paths {
                // Not on a daily schedule: the user chose when checks (and
                // Slack posts) happen, e.g. only at night.
                recheckSoon()
            }
        }
    }
    @Published private(set) var hasSlackToken = false
    @Published private(set) var lastReadings: [DiskMonitorReport.Reading] = []
    @Published private(set) var lastChecked: Date?
    /// When the timer fires next; nil while the monitor is off.
    @Published private(set) var nextCheck: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var slackStatus: String?
    /// The user declined notifications; the tab says so.
    @Published private(set) var notificationsDenied = false

    private var loop: Task<Void, Never>?
    private var pendingRecheck: Task<Void, Never>?
    /// Bumped by every reschedule (enable, disable, interval change). A check
    /// started under an older generation stops at its next await, so it
    /// can't post after the monitor was turned off or overwrite reset state.
    private var generation = 0
    /// A check was asked for while one was running; run once more after it.
    private var recheckQueued = false
    /// Paths whose low state the user has already been notified about. A
    /// notification fires when this set grows; a path is only added once
    /// the notification was actually delivered.
    private var alertingPaths: Set<String> = []
    /// A low-disk notification couldn't be delivered yet (permission still
    /// undetermined); granting permission re-checks right away.
    private var notificationPending = false
    private var topFoldersCache: (date: Date, alerting: Set<String>, top: DiskMonitorReport.TopFolders)?
    private var wakeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, keychain: Keychain = .slack,
         dependencies: Dependencies = Dependencies(), recheckDelay: UInt64 = 1_000_000_000,
         timerSlice: TimeInterval = 60) {
        self.defaults = defaults
        self.keychain = keychain
        self.deps = dependencies
        self.recheckDelay = recheckDelay
        self.timerSlice = timerSlice
        self.settings = DiskMonitorSettings.load(from: defaults)
        // The Keychain is read lazily (`refreshSlackToken`), not here: this
        // object is created at launch, including as the XCTest host.
    }

    // MARK: - Scheduling

    /// Starts the timer if enabled and catches up after sleep. Called once
    /// from `AppDelegate`; safe to call again.
    func start() {
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleWake() }
            }
        }
        guard loop == nil else { return }
        reschedule()
    }

    /// The timer notices an overdue check within one slice; on wake, run it
    /// right away (also a daily check missed while asleep) and restart the
    /// schedule from here.
    func handleWake(now: Date = Date()) {
        guard settings.enabled, let next = nextCheck, now >= next else { return }
        reschedule(checkNow: true)
    }

    /// Restarts the timer. By default an interval schedule checks at once and
    /// a daily one waits for its time, so enabling it at noon doesn't post.
    private func reschedule(checkNow: Bool? = nil) {
        let checkFirst = checkNow ?? (settings.schedule == .interval)
        generation += 1
        loop?.cancel()
        loop = nil
        pendingRecheck?.cancel()
        pendingRecheck = nil
        nextCheck = nil
        guard settings.enabled else {
            // Start fresh next time: a disk still low on re-enable notifies again.
            alertingPaths = []
            notificationPending = false
            lastReadings = []
            topFoldersCache = nil
            recheckQueued = false
            return
        }
        // Only while monitoring: no Keychain access on launch when it's off.
        refreshSlackToken()
        // Ask in parallel, never awaited by the timer: the system prompt only
        // returns once the user answers, and an ignored prompt must not stop
        // monitoring. A first alert sent before the answer isn't delivered,
        // so it is retried on the next check.
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.deps.authorize()
            // The hint reflects the real setting, not a failed request.
            await self.refreshNotificationStatus()
            // Not on a daily schedule: a re-check there would post outside
            // the chosen time; the held-back alert waits for the next run.
            if granted && self.notificationPending && self.settings.enabled && self.settings.schedule == .interval {
                self.recheckSoon()
            }
        }
        loop = Task { [weak self] in
            var runNow = checkFirst
            while !Task.isCancelled {
                let slice: TimeInterval
                do {
                    guard let self else { return }
                    // Unstructured, so cancelling the loop (interval change)
                    // never cancels a Slack post that's already in flight.
                    if runNow { Task { await self.check() } }
                    runNow = true
                    self.nextCheck = self.settings.nextRun(after: self.deps.now())
                    slice = self.timerSlice
                }
                // Wait until `nextCheck` by wall clock, in short slices: one
                // long Task.sleep would not count time the Mac spent asleep.
                while !Task.isCancelled {
                    let remaining: TimeInterval
                    do {
                        guard let self, let next = self.nextCheck else { return }
                        remaining = next.timeIntervalSince(self.deps.now())
                    }
                    if remaining <= 0 { break }
                    try? await Task.sleep(nanoseconds: UInt64(min(remaining, slice) * 1_000_000_000))
                }
            }
        }
    }

    /// A new threshold or volume list takes effect right away instead of at
    /// the next timer tick — otherwise the tab shows "Low disk space" while
    /// notifications and Slack still reflect the old values for up to an
    /// interval. Debounced so a burst of edits sends one report.
    private func recheckSoon() {
        pendingRecheck?.cancel()
        pendingRecheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.recheckDelay ?? 0)
            guard !Task.isCancelled, let self, self.settings.enabled else { return }
            // Unstructured, like the timer's: cancelling this debounce later
            // must not cancel the check (and its Slack post) once started.
            Task { await self.check() }
        }
    }

    /// Re-reads the notification permission (no prompt), e.g. when the
    /// user comes back from System Settings.
    func refreshNotificationStatus() async {
        notificationsDenied = await deps.notificationsDenied()
    }

    // MARK: - Checking

    var isSlackConfigured: Bool { hasSlackToken && !settings.slackChannel.isEmpty }

    var isAlert: Bool {
        DiskMonitorReport.isAlert(lastReadings, threshold: settings.thresholdPercent)
    }

    /// Reads every path, notifies on a new alert and posts to Slack when
    /// configured. Called by the timer, re-checks and "Check Now". If a check
    /// is already running, this one is queued to run right after it.
    func check() async {
        guard !isChecking else {
            recheckQueued = true
            return
        }
        isChecking = true
        defer {
            isChecking = false
            if recheckQueued {
                recheckQueued = false
                if settings.enabled { Task { await self.check() } }
            }
        }

        let gen = generation
        let s = settings
        let readings = await deps.readAll(s.paths)
        guard gen == generation else { return }
        lastReadings = readings
        lastChecked = Date()

        let alerting = Set(readings.filter { $0.isLow(threshold: s.thresholdPercent) }.map(\.path))
        if alerting.isSubset(of: alertingPaths) {
            alertingPaths = alerting
            notificationPending = false
        } else {
            let delivered = await deps.notify(readings, s.thresholdPercent)
            guard gen == generation else {
                // Rescheduled meanwhile (e.g. interval change): the user did
                // see this alert, so don't repeat it on the next check.
                if delivered && settings.enabled { alertingPaths.formUnion(alerting) }
                return
            }
            // Undelivered (e.g. permission not granted yet): keep the new
            // paths out, so the next check tries again.
            alertingPaths = delivered ? alerting : alerting.intersection(alertingPaths)
            notificationPending = !delivered
            if !delivered {
                await refreshNotificationStatus()
                guard gen == generation else { return }
            }
        }

        let alert = !alerting.isEmpty
        guard alert || !s.alertOnly else { return }

        // The report only goes to Slack. Without a token and a channel there is
        // nothing to send, so don't walk the home folder either: it's slow, and
        // without Full Disk Access it can raise macOS privacy prompts.
        let token = keychain.read(Self.tokenAccount)
        hasSlackToken = token != nil
        guard let token, !settings.slackChannel.isEmpty else { return }

        let wantTop = alert && s.includeTopFolders
        let top = wantTop ? await topFolders(alerting: alerting, generation: gen) : nil
        guard gen == generation else { return }
        // Token removed (Remove Token) or channel cleared during the scan: no post.
        guard hasSlackToken, !settings.slackChannel.isEmpty else { return }
        let message = DiskMonitorReport.message(
            host: s.displayName, readings: readings, threshold: s.thresholdPercent,
            topFolders: top, includeTopSection: wantTop, mentions: settings.slackMentions
        )
        await post(message, token: token, channel: settings.slackChannel, success: "Report sent to Slack.")
    }

    /// The cached list while it's fresh and no new path became low;
    /// otherwise a new (time-bounded) scan.
    private func topFolders(alerting: Set<String>, generation gen: Int) async -> DiskMonitorReport.TopFolders? {
        if let cache = topFoldersCache,
           deps.now().timeIntervalSince(cache.date) < Self.topFoldersMaxAge,
           alerting.isSubset(of: cache.alerting) {
            return cache.top
        }
        let top = await deps.scanTopFolders()
        // A stale check (monitor reset meanwhile) must not refill the cache,
        // and a partial list (walk hit its time limit) isn't worth keeping:
        // the next check should try the full walk again.
        if let top, !top.partial, gen == generation { topFoldersCache = (deps.now(), alerting, top) }
        return top
    }

    /// "Send Test Message" — verifies token, channel and bot membership.
    func sendTestMessage() async {
        guard let token = keychain.read(Self.tokenAccount), !settings.slackChannel.isEmpty else {
            slackStatus = "Fill in the bot token and channel, then Save."
            return
        }
        let message = DiskMonitorReport.testMessage(host: settings.displayName)
        await post(message, token: token, channel: settings.slackChannel, success: "Test message sent.")
    }

    private func post(_ message: SlackClient.Message, token: String, channel: String, success: String) async {
        do {
            try await deps.post(message, token, channel)
            slackStatus = success
        } catch {
            logger.error("Slack post failed: \(error.localizedDescription, privacy: .public)")
            slackStatus = Self.explain(error)
        }
    }

    /// Turns the common Slack error codes into something actionable.
    nonisolated static func explain(_ error: Error) -> String {
        guard case SlackClient.SlackError.api(let code) = error else {
            return error.localizedDescription
        }
        switch code {
        case "not_in_channel": return "The bot isn't in that channel. Run /invite @your-bot in Slack."
        case "channel_not_found": return "Channel not found. Check the channel link."
        case "invalid_auth", "not_authed", "token_revoked": return "The bot token was rejected. Check it and save again."
        case "missing_scope": return "The Slack app needs the chat:write scope."
        default: return "Slack error: \(code)."
        }
    }

    /// "Reset to Defaults…": options back to defaults, keeping monitoring
    /// on/off and the Slack connection (see `resetToDefaults`).
    func resetSettings() {
        settings = settings.resetToDefaults()
    }

    // MARK: - Slack token (Keychain)

    /// Re-reads whether a token is stored. Cheap enough for the Slack
    /// section's `onAppear`; kept off the launch path.
    func refreshSlackToken() {
        hasSlackToken = keychain.read(Self.tokenAccount) != nil
    }

    /// Stores a new token. Blank input is ignored — removing the token is
    /// the explicit "Remove Token" button, never a side effect of Save.
    /// The Slack section's Save. The token is stored first and on its own,
    /// so a mistyped channel link or tag never discards a pasted token.
    /// Channel and tags are applied together, only when both are valid.
    /// Returns the error to show, or nil when everything was saved.
    func saveSlack(token: String, channelLink: String, mentions: String) -> String? {
        let tokenGiven = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tokenGiven { saveSlackToken(token) }
        do {
            let ids = try DiskMonitorSettings.parseMentions(mentions)
            var updated = settings
            try updated.applyChannelLink(channelLink)
            updated.slackMentions = ids
            settings = updated
            return nil
        } catch {
            let saved = tokenGiven && hasSlackToken ? " The bot token was saved." : ""
            return error.localizedDescription + saved
        }
    }

    func saveSlackToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if keychain.write(trimmed, for: Self.tokenAccount) {
            hasSlackToken = true
            slackStatus = "Token saved to the Keychain."
        } else {
            slackStatus = "Couldn't save the token to the Keychain."
        }
    }

    func removeSlackToken() {
        if keychain.delete(Self.tokenAccount) {
            hasSlackToken = false
            slackStatus = "Token removed."
        } else {
            slackStatus = "Couldn't remove the token from the Keychain."
        }
    }
}
