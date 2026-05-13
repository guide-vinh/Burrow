import AppKit
import SwiftUI

/// One section card listing every Flutter/Dart project under `~/`,
/// surfaced for cleaning its `.dart_tool` + `build` caches. Discovered
/// alongside node_modules via the unified Scan button on the header.
struct FlutterProjectSection: View {
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
            SectionLabel(text: "Flutter projects (.dart_tool + build)")
            Spacer(minLength: Spacing.sm)
            if !vm.flutterProjects.isEmpty {
                HStack(spacing: Spacing.sm) {
                    BurrowCheckbox(isOn: Binding(
                        get: { vm.allFlutterProjectsSelected },
                        set: { _ in vm.toggleSelectAllFlutterProjects() }
                    ))
                    Text("Select all")
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                        .onTapGesture { vm.toggleSelectAllFlutterProjects() }
                }
                sortMenu
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(CleanViewModel.FlutterSort.allCases) { option in
                Button {
                    vm.flutterSort = option
                } label: {
                    HStack {
                        Text(option.label)
                        if vm.flutterSort == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Sort: \(vm.flutterSort.label)")
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
        if vm.isScanningFlutterProjects && vm.flutterProjects.isEmpty {
            scanningPlaceholder
        } else if vm.flutterProjects.isEmpty {
            emptyPlaceholder
        } else {
            VStack(spacing: 0) {
                ForEach(vm.sortedFlutterProjects) { entry in
                    FlutterProjectRow(
                        entry: entry,
                        isSelected: binding(for: entry.projectURL),
                        onReveal: { reveal(entry.projectURL) }
                    )
                    if entry.projectURL != vm.sortedFlutterProjects.last?.projectURL {
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
            Text("Looking for pubspec.yaml files under ~/ …")
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    private var emptyPlaceholder: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "hammer")
                .foregroundStyle(Color.fgMuted)
            Text("No Flutter projects scanned yet. Click Scan above to find them.")
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
            get: { vm.flutterSelection.contains(url) },
            set: { isOn in
                if isOn { vm.flutterSelection.insert(url) }
                else    { vm.flutterSelection.remove(url) }
            }
        )
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Row

private struct FlutterProjectRow: View {
    let entry: FlutterProjectEntry
    @Binding var isSelected: Bool
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            BurrowCheckbox(isOn: $isSelected)

            Image(systemName: "hammer")
                .font(.system(size: 14))
                .foregroundStyle(Color.fgSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.projectName) · \(entry.cacheTypesLabel)")
                    .font(.bodyM)
                    .foregroundStyle(Color.fgPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(entry.projectURL.path)
                    .font(.captionS)
                    .foregroundStyle(Color.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tooltip("\(entry.projectName) · \(entry.cacheTypesLabel)\n\(entry.projectURL.path)")

            VStack(alignment: .trailing, spacing: 1) {
                Text("project: \(relative(entry.pubspecMtime))")
                Text("cache: \(relative(entry.lastTouchedMtime))")
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

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
