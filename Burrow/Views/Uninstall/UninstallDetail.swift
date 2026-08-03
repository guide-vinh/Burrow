import AppKit
import SwiftUI

/// Right pane of the Uninstall tab. Empty state when no app is
/// selected; otherwise app header + preview banner + leftover list +
/// footer with Preview / Uninstall button.
struct UninstallDetail: View {
    @ObservedObject var vm: UninstallViewModel
    @State private var showConfirmAlert = false
    @State private var permanentDelete = false

    var body: some View {
        if let app = vm.selectedApp {
            content(for: app)
                .alert(
                    "Uninstall \(app.name)?",
                    isPresented: $showConfirmAlert
                ) {
                    Button("Cancel", role: .cancel) {}
                    Button(
                        permanentDelete ? "Delete Permanently" : "Move to Trash",
                        role: .destructive
                    ) {
                        Task { await vm.uninstall(permanently: permanentDelete) }
                    }
                } message: {
                    Text(confirmMessage)
                }
        } else {
            EmptyState(
                icon: "trash",
                title: "Drop an app to uninstall",
                subtitle: "Or pick one from the list on the left.",
                action: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfacePrimary)
        }
    }

    private var confirmMessage: String {
        let count = vm.selectedItemCount
        let word = count == 1 ? "item" : "items"
        let bytes = vm.selectedTotalBytes.formatted(.byteCount(style: .file))
        return permanentDelete
            ? "\(count) \(word) (\(bytes)) will be deleted immediately, bypassing the Trash. This cannot be undone."
            : "\(count) \(word) (\(bytes)) will move to Trash."
    }

    @ViewBuilder
    private func content(for app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            appHeader(for: app)
            Divider().background(Color.borderSubtle)

            if let summary = vm.previewBanner {
                PreviewBanner(
                    summary: summary,
                    actionTitle: "Show in Finder",
                    onAction: { revealApp(app) },
                    onDismiss: { vm.dismissPreviewBanner() }
                )
                Divider().background(Color.borderSubtle)
            }

            leftoverList

            Divider().background(Color.borderSubtle)
            footer
        }
        .background(Color.surfacePrimary)
    }

    private func appHeader(for app: InstalledApp) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.titleM)
                    .foregroundStyle(Color.fgPrimary)
                Text(app.bundleId)
                    .font(.captionM)
                    .foregroundStyle(Color.fgMuted)
                if let version = app.version {
                    Text("Version \(version)")
                        .font(.captionS)
                        .foregroundStyle(Color.fgSecondary)
                }
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                Text("Dry run")
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                BurrowToggle(isOn: $vm.dryRun)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private var leftoverList: some View {
        ScrollView {
            VStack(spacing: Spacing.xs) {
                appBundleRow
                ForEach(vm.leftovers) { match in
                    LeftoverRow(
                        match: match,
                        isChecked: binding(for: match.url)
                    )
                }
            }
            .cardStyle()
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var appBundleRow: some View {
        if let app = vm.selectedApp {
            HStack(spacing: Spacing.md) {
                BurrowCheckbox(isOn: binding(for: app.bundleURL))
                Image(systemName: "app")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.fgSecondary)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(app.name).app")
                        .font(.bodyM)
                        .foregroundStyle(Color.fgPrimary)
                    Text(app.bundleURL.deletingLastPathComponent().path)
                        .font(.captionS)
                        .foregroundStyle(Color.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Spacing.sm)
                if let bytes = app.bundleSize {
                    Text(bytes, format: .byteCount(style: .file))
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                        .frame(minWidth: 70, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .tooltip(app.bundleURL.path)
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            Text(footerText)
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
                .monospacedDigit()
            Spacer()
            Group {
                if vm.dryRun {
                    OutlineButton("Preview", icon: "eye") {
                        Task { await vm.uninstall() }
                    }
                } else {
                    DestructiveButton("Uninstall", icon: "trash") {
                        permanentDelete = false
                        showConfirmAlert = true
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    DestructiveButton("Delete", icon: "trash.slash") {
                        permanentDelete = true
                        showConfirmAlert = true
                    }
                }
            }
            .disabled(vm.selectedItemCount == 0 || vm.isApplying)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }

    private var footerText: String {
        let count = vm.selectedItemCount
        let word = count == 1 ? "item" : "items"
        let bytes = vm.selectedTotalBytes.formatted(.byteCount(style: .file))
        return "\(count) \(word) selected · \(bytes)"
    }

    private func binding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { vm.checkedURLs.contains(url) },
            set: { isOn in
                if isOn { vm.checkedURLs.insert(url) }
                else    { vm.checkedURLs.remove(url) }
            }
        )
    }

    /// Reveal the .app bundle being uninstalled in Finder so the user
    /// can sanity-check which app this is before committing. Falls back
    /// to the operations log if for some reason no app is selected
    /// (shouldn't happen at banner-display time).
    private func revealApp(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
    }
}
