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
                    ForEach(DiskMonitorSettings.thresholdPresets, id: \.self) { value in
                        Text(MenuBarFormat.percent(value)).tag(value)
                    }
                    // A value saved by an earlier version that isn't a choice now.
                    if !DiskMonitorSettings.thresholdPresets.contains(vm.settings.thresholdPercent) {
                        Text(MenuBarFormat.percent(vm.settings.thresholdPercent)).tag(vm.settings.thresholdPercent)
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
                            .tooltip("Once a day at this time. If the Mac is asleep then, the check runs when it wakes.")
                    }
                }

                HStack {
                    // Short label so it fits on one line next to the field and
                    // Set button; the placeholder shows the comma-separated form.
                    TextField("Volumes", text: $pathsDraft, prompt: Text("/, /Volumes/Data"))
                        .onSubmit(applyPaths)
                    Button("Set", action: applyPaths)
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
            Text("Threshold, schedule, volumes, name in reports and display options go back to their defaults. Whether monitoring is on and your Slack settings are kept.")
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
/// Channel and tags are drafts applied on Save; the token goes straight to
/// the Keychain and is never shown again.
struct MonitoringSlackSection: View {
    @ObservedObject var vm: DiskMonitorViewModel

    @State private var tokenDraft = ""
    @State private var channelDraft = ""
    @State private var mentionsDraft = ""
    @State private var slackError: String?

    var body: some View {
        Section("Slack (optional)") {
            Text("Leave empty to get macOS notifications only. The Slack app needs the chat:write scope, and the bot must be invited to the channel.")
                .font(.captionM)
                .foregroundStyle(Color.fgSecondary)

            SecureField("Bot token", text: $tokenDraft,
                        prompt: Text(vm.hasSlackToken ? "Saved in Keychain" : "xoxb-…"))
            TextField("Channel link", text: $channelDraft, prompt: Text("https://…slack.com/archives/C0123ABCD"))
            TextField("Tag on alerts", text: $mentionsDraft, prompt: Text("U0123ABCD, S0456EFGH"))

            Toggle("Only post when space is low", isOn: $vm.settings.alertOnly)
            Toggle("Include largest folders on alerts", isOn: $vm.settings.includeTopFolders)

            HStack {
                if vm.hasSlackToken {
                    Button("Remove Token") { vm.removeSlackToken() }
                }
                Spacer()
                Button("Send Test Message") { Task { await vm.sendTestMessage() } }
                    .disabled(!vm.isSlackConfigured || hasUnsavedSlackEdits)
                Button("Save", action: saveSlack)
                    .disabled(!hasUnsavedSlackEdits)
            }

            if hasUnsavedSlackEdits {
                Text("Save to apply your changes before sending a test.")
                    .font(.captionM)
                    .foregroundStyle(Color.fgMuted)
            }
            if let slackError {
                errorText(slackError)
            } else if let status = vm.slackStatus {
                Text(status).font(.captionM).foregroundStyle(Color.fgSecondary)
            }
        }
        .onChange(of: channelDraft) { _ in slackError = nil }
        .onChange(of: mentionsDraft) { _ in slackError = nil }
        .onAppear {
            vm.refreshSlackToken()
            channelDraft = vm.settings.slackChannelLink
            mentionsDraft = vm.settings.slackMentions.joined(separator: ", ")
        }
    }

    private var hasUnsavedSlackEdits: Bool {
        !trimmed(tokenDraft).isEmpty
            || trimmed(channelDraft) != vm.settings.slackChannelLink
            || (try? DiskMonitorSettings.parseMentions(mentionsDraft)) != vm.settings.slackMentions
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveSlack() {
        do {
            let mentions = try DiskMonitorSettings.parseMentions(mentionsDraft)
            try vm.settings.applyChannelLink(channelDraft)
            slackError = nil
            vm.settings.slackMentions = mentions
            channelDraft = vm.settings.slackChannelLink
            // Blank input never deletes the stored token; that's Remove Token.
            vm.saveSlackToken(tokenDraft)
            tokenDraft = ""
        } catch {
            slackError = error.localizedDescription
        }
    }
}

/// Red caption under a field, shared by both sections.
private func errorText(_ message: String) -> some View {
    Text(message).font(.captionM).foregroundStyle(Color.destructive)
}
