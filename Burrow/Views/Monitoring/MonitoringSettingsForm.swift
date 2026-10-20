import AppKit
import SwiftUI

/// The "Disk Monitor" section of the Monitoring tab (left column). Text
/// fields edit local drafts that are validated on Set, with the same rules
/// as diskmon (see `DiskMonitorSettings`).
struct MonitoringGeneralSection: View {
    @ObservedObject var vm: DiskMonitorViewModel

    @State private var pathsDraft = ""
    @State private var nameDraft = ""
    @State private var nameSave: Task<Void, Never>?
    /// The name as loaded into this view. Only a draft that differs from it
    /// was typed here, so an untouched draft (e.g. in a second window) never
    /// overwrites a name saved elsewhere.
    @State private var nameLoaded = ""
    @State private var confirmReset = false

    var body: some View {
        Section("Disk Monitor") {
            Toggle("Watch free disk space", isOn: $vm.settings.enabled)

            if vm.settings.enabled {
                if vm.notificationsDenied {
                    Text("Notifications are off for Burrow. Turn them on in System Settings → Notifications to get low-disk alerts.")
                        .font(.captionM)
                        .foregroundStyle(Color.destructive)
                }

                Picker("Alert when free space ≤", selection: $vm.settings.thresholdPercent) {
                    // A value saved by an earlier version that isn't a choice
                    // now is listed too, in order.
                    ForEach(thresholdChoices, id: \.self) { value in
                        Text(MenuBarFormat.percent(value)).tag(value)
                    }
                }

                // Schedule mode and its value on one row, so the column fits
                // the default window height without scrolling.
                HStack(spacing: Spacing.sm) {
                    Text("Check")
                    Spacer(minLength: Spacing.sm)
                    Picker("Schedule", selection: $vm.settings.schedule) {
                        ForEach(DiskMonitorSettings.Schedule.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    // Fixed width, so the segmented control doesn't shift when
                    // the control next to it changes.
                    Group {
                        switch vm.settings.schedule {
                        case .interval:
                            Picker("Check every", selection: $vm.settings.intervalMinutes) {
                                ForEach(DiskMonitorSettings.intervalPresets, id: \.self) { minutes in
                                    Text(intervalLabel(minutes)).tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        case .daily:
                            DatePicker("Check at", selection: dailyTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .fixedSize()
                                .tooltip("Once a day at this time. If the Mac is asleep or Burrow isn't running then, the check runs when it wakes or opens.")
                        }
                    }
                    .frame(width: 112, alignment: .trailing)
                }

                HStack {
                    // Short label so it fits on one line next to the field and
                    // Set button; the placeholder shows the comma-separated form.
                    TextField("Paths", text: $pathsDraft, prompt: Text("/, /Volumes/Data"))
                        .onSubmit(applyPaths)
                    Button("Set", action: applyPaths)
                }
                if !missingPaths.isEmpty {
                    Text("Not found: \(missingPaths.joined(separator: ", ")). It's checked anyway and reported as unreadable until it's there.")
                        .font(.captionM)
                        .foregroundStyle(Color.fgMuted)
                }

                // A draft, saved shortly after typing stops (and on Return or
                // leaving the tab) — not a UserDefaults write per keystroke,
                // yet not lost if the app quits right away.
                TextField("Name in reports", text: $nameDraft, prompt: Text(DiskMonitorSettings.computerName))
                    .onSubmit(applyName)
                    .onChange(of: nameDraft) { _ in scheduleNameSave() }

                Toggle("Show in menu bar", isOn: $vm.settings.showInMenuBar)

                Picker("Show percentage as", selection: $vm.settings.percentDisplay) {
                    ForEach(DiskMonitorSettings.PercentDisplay.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Spacer()
                    Button("Reset to Defaults…") { confirmReset = true }
                }
            }
        }
        .alert("Reset Monitoring settings?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { vm.resetSettings() }
        } message: {
            Text("Threshold, schedule, volumes, name in reports and display options go back to their defaults. Whether monitoring is on and your Slack settings are kept. If monitoring is on, it may check right away, which can notify or post to Slack.")
        }
        .onAppear(perform: loadDrafts)
        // A reset (or the menu bar) can change these while the tab is open.
        .onChange(of: vm.settings.paths) { _ in pathsDraft = vm.settings.paths.joined(separator: ", ") }
        // Only when it differs from what's being typed: saving trims the
        // draft, and reloading then would eat a trailing space mid-typing.
        .onChange(of: vm.settings.machineName) { saved in
            if saved != nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) { loadName() }
        }
        .onDisappear(perform: applyName)
    }

    private var thresholdChoices: [Double] {
        Array(Set(DiskMonitorSettings.thresholdPresets + [vm.settings.thresholdPercent])).sorted()
    }

    /// Entered paths that don't exist right now (e.g. a typo, or a volume
    /// that isn't mounted).
    private var missingPaths: [String] {
        vm.settings.paths.filter {
            !FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath)
        }
    }

    private func applyPaths() {
        vm.settings.paths = DiskMonitorSettings.parsePaths(pathsDraft)
        pathsDraft = vm.settings.paths.joined(separator: ", ")
    }

    private func applyName() {
        nameSave?.cancel()
        guard nameDraft != nameLoaded else { return }
        vm.settings.machineName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        nameLoaded = nameDraft
    }

    private func scheduleNameSave() {
        nameSave?.cancel()
        nameSave = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            applyName()
        }
    }

    private func loadDrafts() {
        pathsDraft = vm.settings.paths.joined(separator: ", ")
        loadName()
    }

    private func loadName() {
        nameDraft = vm.settings.machineName
        nameLoaded = nameDraft
    }

    /// `dailyMinute` (minutes after midnight) as a time-of-day for DatePicker.
    private var dailyTime: Binding<Date> {
        Binding(
            get: {
                let m = vm.settings.dailyMinute
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                vm.settings.dailyMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

/// The optional "Slack" section of the Monitoring tab (right column).
/// Each field saves itself once the user is done with it: on Return, when
/// focus leaves it, and when the tab closes or the app quits; the channel and
/// tags also save a moment after typing stops. The token never does — a
/// half-typed one would replace a good token. Save still applies everything
/// at once. The token goes straight to the Keychain and is never shown again.
struct MonitoringSlackSection: View {
    @ObservedObject var vm: DiskMonitorViewModel

    private enum Field { case token, channel, mentions }

    @State private var tokenDraft = ""
    @State private var channelDraft = ""
    @State private var mentionsDraft = ""
    @State private var tokenError: String?
    @State private var channelError: String?
    @State private var mentionsError: String?
    @State private var pendingSave: Task<Void, Never>?
    @FocusState private var focus: Field?

    /// How long after the last keystroke a field saves itself.
    private static let saveDelay: UInt64 = 1_000_000_000

    var body: some View {
        Section("Slack (optional)") {
            Text("Leave empty to get macOS notifications only. The Slack app needs the chat:write scope, and the bot must be invited to the channel.")
                .font(.captionM)
                .foregroundStyle(Color.fgSecondary)

            SecureField("Bot token", text: $tokenDraft,
                        prompt: Text(vm.hasSlackToken ? "Saved in Keychain" : "xoxb-…"))
                .focused($focus, equals: .token)
                .onSubmit { saveAll() }
            if let tokenError { errorText(tokenError) }

            TextField("Channel link", text: $channelDraft, prompt: Text("https://…slack.com/archives/C0123ABCD"))
                .focused($focus, equals: .channel)
                .onSubmit { saveAll() }
            if let channelError { errorText(channelError) }

            TextField("Tag on alerts", text: $mentionsDraft, prompt: Text("U0123ABCD, S0456EFGH"))
                .focused($focus, equals: .mentions)
                .onSubmit { saveAll() }
            if let mentionsError { errorText(mentionsError) }

            Toggle("Only post when space is low", isOn: $vm.settings.alertOnly)
            Toggle("Include largest folders on alerts", isOn: $vm.settings.includeTopFolders)

            HStack {
                if vm.hasSlackToken {
                    Button("Remove Token", action: removeToken)
                }
                Spacer()
                Button("Send Test Message") { Task { await vm.sendTestMessage() } }
                    .disabled(!vm.isSlackConfigured || hasUnsavedSlackEdits)
                Button("Save") { saveAll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedSlackEdits)
            }

            if let hint = pendingHint {
                Text(hint)
                    .font(.captionM)
                    .foregroundStyle(Color.fgMuted)
            } else if !hasErrors, let status = vm.slackStatus {
                Text(status).font(.captionM).foregroundStyle(Color.fgSecondary)
            }
        }
        .onChange(of: tokenDraft) { _ in tokenError = nil }
        .onChange(of: channelDraft) { _ in channelError = nil; scheduleSave() }
        .onChange(of: mentionsDraft) { _ in mentionsError = nil; scheduleSave() }
        // Leaving a field counts as done with it.
        .onChange(of: focus) { field in saveAll(commitToken: field != .token) }
        .onAppear {
            vm.refreshSlackToken()
            channelDraft = vm.settings.slackChannelLink
            mentionsDraft = vm.settings.slackMentions.joined(separator: ", ")
        }
        .onDisappear { saveAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveAll()
        }
    }

    private var hasErrors: Bool { tokenError != nil || channelError != nil || mentionsError != nil }

    private var hasUnsavedSlackEdits: Bool {
        !trimmed(tokenDraft).isEmpty
            || trimmed(channelDraft) != vm.settings.slackChannelLink
            || (try? DiskMonitorSettings.parseMentions(mentionsDraft)) != vm.settings.slackMentions
    }

    /// What to tell the user about edits that will be saved without them
    /// pressing anything. Nil when nothing is pending or every pending draft
    /// is invalid (those show an error instead and are never saved).
    private var pendingHint: String? {
        var tokenPending = false
        if case .save = DiskMonitorSettings.tokenCommit(draft: tokenDraft, finished: true) { tokenPending = true }
        let channelPending = trimmed(channelDraft) != vm.settings.slackChannelLink
            && (try? DiskMonitorSettings.parseChannel(channelDraft)) != nil
        let mentionsPending = (try? DiskMonitorSettings.parseMentions(mentionsDraft))
            .map { $0 != vm.settings.slackMentions } ?? false
        let autoSaves = channelPending || mentionsPending

        switch (autoSaves, tokenPending) {
        case (true, true): return "The token saves when you press Return or leave the field; the rest saves when you finish typing."
        case (true, false): return "Saves automatically when you finish typing."
        case (false, true): return "The token saves when you press Return or leave the field."
        case (false, false): return nil
        }
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(nanoseconds: Self.saveDelay)
            guard !Task.isCancelled else { return }
            save(finished: false)
        }
    }

    /// The user is done (Return, focus moved, Save, tab closed, app quitting).
    /// `commitToken` is false when focus just moved *into* the token field.
    private func saveAll(commitToken: Bool = true) {
        pendingSave?.cancel()
        save(finished: true, commitToken: commitToken)
    }

    /// Drops any typed token (and the saves waiting on it) so it can't be
    /// written back right after the stored one is removed. A pending channel
    /// or tags edit is saved first, so it isn't lost either.
    private func removeToken() {
        tokenDraft = ""
        tokenError = nil
        saveAll()
        vm.removeSlackToken()
    }

    /// Saves each edited field on its own, so a mistake in one doesn't hold
    /// back the others. While the user may still be typing (`finished` is
    /// false) an invalid value is just left unsaved, without an error, and
    /// no draft is rewritten under the cursor. The token is only ever
    /// committed on a finished save.
    private func save(finished: Bool, commitToken: Bool = true) {
        var savedSettings = false

        if commitToken {
            switch DiskMonitorSettings.tokenCommit(draft: tokenDraft, finished: finished) {
            case .none:
                break
            case .save(let token):
                // Clear the field so it shows "Saved in Keychain".
                if vm.saveSlackToken(token) { tokenDraft = "" }
            case .invalid:
                tokenError = DiskMonitorSettings.ValidationError.token.localizedDescription
            }
        }

        if trimmed(channelDraft) != vm.settings.slackChannelLink {
            do {
                try vm.settings.applyChannelLink(channelDraft)
                savedSettings = true
                if finished { channelDraft = vm.settings.slackChannelLink }
            } catch {
                if finished { channelError = error.localizedDescription }
            }
        }

        do {
            let mentions = try DiskMonitorSettings.parseMentions(mentionsDraft)
            if mentions != vm.settings.slackMentions {
                vm.settings.slackMentions = mentions
                savedSettings = true
            }
            if finished { mentionsDraft = mentions.joined(separator: ", ") }
        } catch {
            if finished { mentionsError = error.localizedDescription }
        }

        if savedSettings { vm.noteSlackSettingsSaved() }
    }
}

/// Red caption under a field, shared by both sections.
private func errorText(_ message: String) -> some View {
    Text(message).font(.captionM).foregroundStyle(Color.destructive)
}
