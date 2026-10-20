import AppKit
import SwiftUI

/// The "Disk Monitor" section of the Monitoring tab (left column). Text
/// fields edit local drafts that are validated on Set, with the same rules
/// as diskmon (see `DiskMonitorSettings`).
struct MonitoringGeneralSection: View {
    @ObservedObject var vm: DiskMonitorViewModel

    @State private var customThreshold = ""
    @State private var thresholdError: String?
    @State private var pathsDraft = ""
    @State private var nameDraft = ""
    @State private var nameSave: Task<Void, Never>?
    /// The name as loaded into this view. Only a draft that differs from it
    /// was typed here, so an untouched draft (e.g. in a second window) never
    /// overwrites a name saved elsewhere.
    @State private var nameLoaded = ""

    var body: some View {
        Section("Disk Monitor") {
            Toggle("Watch free disk space", isOn: $vm.settings.enabled)

            if vm.settings.enabled {
                if vm.notificationsDenied {
                    Text("Notifications are off for Burrow. Turn them on in System Settings → Notifications to get low-disk alerts.")
                        .font(.captionM)
                        .foregroundStyle(Color.destructive)
                }

                Picker("Alert when free space is at or below", selection: $vm.settings.thresholdPercent) {
                    ForEach(DiskMonitorSettings.thresholdPresets, id: \.self) { value in
                        Text(MenuBarFormat.percent(value)).tag(value)
                    }
                    if !DiskMonitorSettings.thresholdPresets.contains(vm.settings.thresholdPercent) {
                        Text(MenuBarFormat.percent(vm.settings.thresholdPercent)).tag(vm.settings.thresholdPercent)
                    }
                }
                HStack {
                    TextField("Custom threshold", text: $customThreshold, prompt: Text("e.g. 7.5"))
                        .onSubmit(applyCustomThreshold)
                        .onChange(of: customThreshold) { _ in thresholdError = nil }
                    Button("Set", action: applyCustomThreshold)
                        .disabled(customThreshold.isEmpty)
                }
                if let thresholdError { errorText(thresholdError) }

                Picker("Check every", selection: $vm.settings.intervalMinutes) {
                    ForEach(DiskMonitorSettings.intervalPresets, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                }

                HStack {
                    TextField("Volumes (comma-separated)", text: $pathsDraft, prompt: Text("/"))
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
            }
        }
        .onAppear {
            pathsDraft = vm.settings.paths.joined(separator: ", ")
            nameDraft = vm.settings.machineName
            nameLoaded = nameDraft
        }
        .onDisappear(perform: applyName)
    }

    private func applyCustomThreshold() {
        do {
            vm.settings.thresholdPercent = try DiskMonitorSettings.parseThreshold(customThreshold)
            customThreshold = ""
        } catch {
            thresholdError = error.localizedDescription
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

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

/// The optional "Slack" section of the Monitoring tab (right column).
/// Each field saves itself once the user is done with it: on Return, when
/// focus leaves it, a moment after typing stops, and when the tab closes or
/// the app quits. Save still applies everything at once. The token goes
/// straight to the Keychain and is never shown again.
struct MonitoringSlackSection: View {
    @ObservedObject var vm: DiskMonitorViewModel

    private enum Field { case token, channel, mentions }

    @State private var tokenDraft = ""
    /// The draft last written to the Keychain by a save while typing; the
    /// field keeps showing it until the user moves on.
    @State private var savedTokenDraft = ""
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
                    Button("Remove Token") { vm.removeSlackToken() }
                }
                Spacer()
                Button("Send Test Message") { Task { await vm.sendTestMessage() } }
                    .disabled(!vm.isSlackConfigured || hasUnsavedSlackEdits)
                Button("Save") { saveAll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedSlackEdits)
            }

            if hasUnsavedSlackEdits && !hasErrors {
                Text("Saves automatically when you finish typing.")
                    .font(.captionM)
                    .foregroundStyle(Color.fgMuted)
            } else if let status = vm.slackStatus {
                Text(status).font(.captionM).foregroundStyle(Color.fgSecondary)
            }
        }
        .onChange(of: tokenDraft) { _ in tokenError = nil; scheduleSave() }
        .onChange(of: channelDraft) { _ in channelError = nil; scheduleSave() }
        .onChange(of: mentionsDraft) { _ in mentionsError = nil; scheduleSave() }
        // Leaving a field counts as done with it.
        .onChange(of: focus) { _ in saveAll() }
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
        (!trimmed(tokenDraft).isEmpty && tokenDraft != savedTokenDraft)
            || trimmed(channelDraft) != vm.settings.slackChannelLink
            || (try? DiskMonitorSettings.parseMentions(mentionsDraft)) != vm.settings.slackMentions
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
    private func saveAll() {
        pendingSave?.cancel()
        save(finished: true)
    }

    /// Saves each edited field on its own, so a mistake in one doesn't hold
    /// back the others. While the user may still be typing (`finished` is
    /// false) an invalid value is just left unsaved, without an error, and
    /// no draft is rewritten under the cursor.
    private func save(finished: Bool) {
        var savedSettings = false

        let token = trimmed(tokenDraft)
        if !token.isEmpty, tokenDraft != savedTokenDraft {
            do {
                if vm.saveSlackToken(try DiskMonitorSettings.parseToken(token)) {
                    savedTokenDraft = tokenDraft
                }
            } catch {
                if finished { tokenError = error.localizedDescription }
            }
        }
        if finished, !tokenDraft.isEmpty, tokenDraft == savedTokenDraft {
            // Saved: clear the field so it shows "Saved in Keychain".
            tokenDraft = ""
            savedTokenDraft = ""
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
