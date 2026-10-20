import AppKit
import SwiftUI

/// Top-level view for the Monitoring tab: live free-space readings for the
/// watched volumes plus the monitor's configuration. Off by default; every
/// value is filled in by the user. Slack is optional — without it the
/// monitor only raises macOS notifications.
struct MonitoringView: View {

    @ObservedObject var vm: DiskMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            // Two columns so everything fits the default 1200×720 window
            // without scrolling: status + general settings | Slack.
            HStack(alignment: .top, spacing: Spacing.lg) {
                Form {
                    if vm.settings.enabled && !vm.lastReadings.isEmpty {
                        Section("Volumes") {
                            ForEach(Array(vm.lastReadings.enumerated()), id: \.offset) { _, reading in
                                VolumeRow(reading: reading, threshold: vm.settings.thresholdPercent,
                                      display: vm.settings.percentDisplay)
                            }
                        }
                    }
                    MonitoringGeneralSection(vm: vm)
                }
                .monitoringFormStyle()

                if vm.settings.enabled {
                    Form { MonitoringSlackSection(vm: vm) }
                        .monitoringFormStyle()
                }
            }
        }
        // Pick up a permission change made in System Settings.
        .task { await vm.refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await vm.refreshNotificationStatus() }
        }
        .padding(.horizontal, Spacing.xxl + Spacing.sm)
        .padding(.vertical, Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfacePrimary)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Monitoring")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fgPrimary)
                // Re-rendered every 30 s so "checked 2 minutes ago" stays true.
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(summary)
                        .font(.bodyM)
                        .foregroundStyle(vm.settings.enabled && vm.isAlert ? Color.destructive : Color.fgSecondary)
                }
            }
            Spacer(minLength: Spacing.sm)
            if vm.settings.enabled {
                if vm.isChecking {
                    ProgressView().controlSize(.small).padding(.trailing, Spacing.xs)
                }
                OutlineButton("Check Now") { Task { await vm.check() } }
                    .disabled(vm.isChecking)
            }
        }
    }

    private var summary: String {
        guard vm.settings.enabled else {
            return "Get notified — and optionally post to Slack — when a disk runs low."
        }
        guard let last = vm.lastChecked else {
            // A daily schedule waits for its time instead of checking at once.
            if let next = vm.nextCheck {
                return "First check at \(next.formatted(date: .omitted, time: .shortened))"
            }
            return "Waiting for the first check…"
        }
        let state = vm.isAlert ? "Low disk space" : "All volumes have enough free space"
        return "\(state) · checked \(last.formatted(.relative(presentation: .named)))"
    }
}

/// One watched volume: path, a usage bar and the free-space figures.
private struct VolumeRow: View {
    let reading: DiskMonitorReport.Reading
    let threshold: Double
    let display: DiskMonitorSettings.PercentDisplay

    private var isLow: Bool { reading.isLow(threshold: threshold) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(reading.path).font(.bodySMed).foregroundStyle(Color.fgPrimary)
                Spacer()
                Text(detail)
                    .font(.captionM)
                    .foregroundStyle(isLow ? Color.destructive : Color.fgSecondary)
                    .monospacedDigit()
            }
            if !reading.failed {
                // Drawn like Analyze's capacity bar (CapacitySummaryCard), and
                // like it always fills the used share: Used/Free only changes
                // the label. A native ProgressView ignores tint on macOS 12.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.surfaceTertiary)
                        Capsule()
                            .fill(isLow ? Color.destructive : Color.accentPrimary)
                            .frame(width: max(0, geometry.size.width * fraction))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var detail: String {
        reading.failed ? "Couldn't be read" : MenuBarFormat.usage(reading, display)
    }

    /// Share of the bar to fill: always the space used.
    private var fraction: Double {
        min(max(reading.usedPercent, 0), 100) / 100
    }
}

private extension View {
    /// Shared look of both Monitoring columns.
    func monitoringFormStyle() -> some View {
        groupedFormStyle()
            // Burrow's palette is light-only; without this, native form
            // controls follow system Dark Mode and draw white-on-white.
            .environment(\.colorScheme, .light)
            .tint(Color.accentPrimary)
            // Without an explicit height a Form collapses to zero inside the
            // stack and nothing below the header renders.
            .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Grouped, scrollable form on macOS 13+; macOS 12 keeps the default.
    @ViewBuilder
    func groupedFormStyle() -> some View {
        if #available(macOS 13.0, *) {
            formStyle(.grouped).scrollContentBackground(.hidden)
        } else {
            // macOS 12's Form doesn't scroll; keep Save / Send Test reachable
            // on short windows.
            ScrollView { self.padding(.vertical, Spacing.sm) }
        }
    }
}
