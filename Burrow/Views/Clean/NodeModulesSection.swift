import AppKit
import SwiftUI

/// One section card listing every `node_modules` directory under `~/`.
/// Discovered lazily via `vm.scanNodeModules()` (long-running on large
/// home dirs) and rendered as a sortable list with per-row checkboxes.
struct NodeModulesSection: View {
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            card
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            SectionLabel(text: "Project caches (node_modules)")
            Spacer(minLength: Spacing.sm)
            if !vm.nodeModulesEntries.isEmpty {
                sortMenu
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(CleanViewModel.NodeModulesSort.allCases) { option in
                Button {
                    vm.nodeModulesSort = option
                } label: {
                    HStack {
                        Text(option.label)
                        if vm.nodeModulesSort == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Sort: \(vm.nodeModulesSort.label)")
                Image(systemName: "chevron.down")
            }
            .font(.bodyS)
            .foregroundStyle(Color.fgSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Card

    @ViewBuilder
    private var card: some View {
        if vm.isScanningNodeModules && vm.nodeModulesEntries.isEmpty {
            scanningPlaceholder
        } else if vm.nodeModulesEntries.isEmpty {
            emptyPlaceholder
        } else {
            VStack(spacing: 0) {
                ForEach(vm.sortedNodeModules) { entry in
                    NodeModulesRow(
                        entry: entry,
                        isSelected: binding(for: entry.url),
                        onReveal: { reveal(entry.url) }
                    )
                    if entry.url != vm.sortedNodeModules.last?.url {
                        Divider().background(Color.borderSubtle)
                    }
                }
            }
            .cardStyle()
        }
    }

    private var scanningPlaceholder: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Walking ~/ — this can take a minute on a big home dir.")
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    private var emptyPlaceholder: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "shippingbox")
                .foregroundStyle(Color.fgMuted)
            Text("No node_modules scanned yet. Click Scan above to find them.")
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    // MARK: - Helpers

    private func binding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { vm.nodeModulesSelection.contains(url) },
            set: { isOn in
                if isOn { vm.nodeModulesSelection.insert(url) }
                else    { vm.nodeModulesSelection.remove(url) }
            }
        )
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Row

private struct NodeModulesRow: View {
    let entry: NodeModulesEntry
    @Binding var isSelected: Bool
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            BurrowCheckbox(isOn: $isSelected)

            Image(systemName: "shippingbox")
                .font(.system(size: 14))
                .foregroundStyle(Color.fgSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.parentName)/node_modules")
                    .font(.bodyM)
                    .foregroundStyle(Color.fgPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(entry.url.path)
                    .font(.captionS)
                    .foregroundStyle(Color.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tooltip("\(entry.parentName)/node_modules\n\(entry.url.path)")

            VStack(alignment: .trailing, spacing: 1) {
                Text("project: \(relative(entry.parentMtime))")
                Text("nm: \(relative(entry.nodeModulesMtime))")
            }
            .font(.captionS)
            .foregroundStyle(Color.fgMuted)
            .frame(width: 130, alignment: .trailing)

            Text(entry.totalBytes, format: .byteCount(style: .file))
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
                .frame(minWidth: 70, alignment: .trailing)
                .monospacedDigit()

            Button(action: onReveal) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fgMuted)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    /// Coarse "N days ago" / "N weeks ago" formatting; we don't need
    /// minute precision for project mtimes.
    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
