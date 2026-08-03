import SwiftUI

/// Right column: the "Largest Folders" header with a sort menu, followed by
/// one card per folder. Each row expands to reveal its biggest subfolders,
/// so the user can drill into where the space actually concentrates.
struct LargestFoldersList: View {

    @ObservedObject var vm: AnalyzeViewModel
    @State private var expanded: Set<URL> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if vm.largestFolders.isEmpty {
                Text(vm.isScanning ? "Sizing folders…" : "No folders found in your home directory.")
                    .font(.bodyS)
                    .foregroundStyle(Color.fgMuted)
                    .padding(.vertical, Spacing.lg)
            } else {
                VStack(spacing: Spacing.sm + 2) {
                    ForEach(vm.displayedFolders, id: \.url) { folder in
                        FolderDisclosure(
                            vm: vm,
                            folder: folder,
                            fraction: vm.maxFolderSize > 0
                                ? Double(folder.size) / Double(vm.maxFolderSize) : 0,
                            depth: 0,
                            expanded: $expanded
                        )
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text("Largest Folders")
                .font(.titleM)
                .foregroundStyle(Color.fgPrimary)
            Spacer(minLength: 0)
            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AnalyzeViewModel.FolderSort.allCases) { order in
                Button(order.label) { vm.sortOrder = order }
            }
        } label: {
            HStack(spacing: Spacing.xs + 2) {
                Text(vm.sortOrder.label)
                    .font(.captionM.weight(.medium))
                    .foregroundStyle(Color.fgSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fgMuted)
            }
            .padding(.horizontal, Spacing.md - 2)
            .padding(.vertical, Spacing.sm - 2)
            .borderedCard(cornerRadius: Radius.sm)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Recursive disclosure

/// One folder row plus, when expanded, an indented list of its largest
/// subfolders (each itself a `FolderDisclosure`, so drill-down is recursive).
private struct FolderDisclosure: View {
    @ObservedObject var vm: AnalyzeViewModel
    let folder: DiskEntry
    let fraction: Double
    let depth: Int
    @Binding var expanded: Set<URL>

    private var isExpanded: Bool { expanded.contains(folder.url) }

    var body: some View {
        VStack(spacing: Spacing.xs + 2) {
            FolderRow(
                folder: folder,
                fraction: fraction,
                depth: depth,
                isExpanded: isExpanded,
                onToggle: toggle,
                onOpen: { vm.openInFinder(folder) },
                onReveal: { vm.revealInFinder(folder) },
                onTrash: { Task { await vm.moveToTrash(folder) } },
                onDelete: { Task { await vm.deletePermanently(folder) } }
            )
            if isExpanded {
                expandedContent
                    .padding(.leading, Spacing.lg + 4)
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if vm.isLoadingChildren(folder) {
            HStack(spacing: Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Loading subfolders…")
                    .font(.captionM)
                    .foregroundStyle(Color.fgMuted)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.sm)
        } else {
            let children = vm.children(of: folder)
            if children.isEmpty {
                HStack {
                    Text("No subfolders")
                        .font(.captionM)
                        .foregroundStyle(Color.fgMuted)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.xs)
            } else {
                VStack(spacing: Spacing.xs + 2) {
                    ForEach(children, id: \.url) { child in
                        FolderDisclosure(
                            vm: vm,
                            folder: child,
                            fraction: folder.size > 0
                                ? Double(child.size) / Double(folder.size) : 0,
                            depth: depth + 1,
                            expanded: $expanded
                        )
                    }
                }
            }
        }
    }

    private func toggle() {
        if isExpanded {
            expanded.remove(folder.url)
        } else {
            expanded.insert(folder.url)
            Task { await vm.loadChildrenIfNeeded(folder) }
        }
    }
}

// MARK: - Row

private struct FolderRow: View {
    let folder: DiskEntry
    let fraction: Double
    let depth: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onTrash: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var compact: Bool { depth > 0 }
    private var style: (icon: String, tint: Color) { FolderIconStyle.style(for: folder) }
    private var iconSide: CGFloat { compact ? 28 : 36 }

    var body: some View {
        VStack(spacing: compact ? Spacing.xs + 1 : Spacing.sm + 2) {
            HStack(spacing: Spacing.sm + 2) {
                disclosure
                iconBox
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(compact ? .bodyS : .bodyM.weight(.medium))
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if depth == 0 {
                        Text(abbreviatedParent)
                            .font(.captionM)
                            .foregroundStyle(Color.fgMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Text(folder.humanSize)
                    .font(compact ? .bodySMed : .bodyM.weight(.semibold))
                    .foregroundStyle(Color.fgPrimary)
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: compact ? 14 : 16, weight: .medium))
                        .foregroundStyle(Color.fgMuted)
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceTertiary)
                    Capsule()
                        .fill(style.tint)
                        .frame(width: max(0, geometry.size.width * fraction))
                }
            }
            .frame(height: compact ? 4 : 6)
        }
        .padding(.vertical, compact ? Spacing.sm + 1 : Spacing.md + 2)
        .padding(.horizontal, compact ? Spacing.md : Spacing.lg + 2)
        .modifier(RowSurface(compact: compact))
        .contextMenu {
            Button("Open in Finder", action: onOpen)
            Button("Reveal in Finder", action: onReveal)
            Button("Move to Trash", role: .destructive, action: onTrash)
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .alert("Delete \(folder.name)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("\(folder.humanSize) will be deleted immediately, bypassing the Trash. This cannot be undone.")
        }
    }

    /// Expand/collapse chevron. Every row is a folder, so it can always be
    /// drilled into (an empty folder simply shows "No subfolders").
    private var disclosure: some View {
        Button(action: onToggle) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.fgMuted)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(style.tint.opacity(0.12))
            Image(systemName: style.icon)
                .font(.system(size: compact ? 13 : 16, weight: .medium))
                .foregroundStyle(style.tint)
        }
        .frame(width: iconSide, height: iconSide)
    }

    /// Parent directory, home-abbreviated to `~/…`.
    private var abbreviatedParent: String {
        let parent = folder.parentURL ?? folder.url.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var path = parent.standardizedFileURL.path
        if path == home {
            return "~"
        } else if path.hasPrefix(home + "/") {
            path = "~/" + String(path.dropFirst(home.count + 1))
        }
        return path
    }
}

/// Top-level rows get the bordered card; nested rows use a lighter inset fill.
private struct RowSurface: ViewModifier {
    let compact: Bool
    func body(content: Content) -> some View {
        if compact {
            content.background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.surfaceSecondary)
            )
        } else {
            content.borderedCard()
        }
    }
}

// MARK: - Icon + tint per folder

/// Maps a folder to a representative SF Symbol + accent tint by name/path,
/// falling back to a generic folder with the entry's deterministic color.
enum FolderIconStyle {
    static func style(for entry: DiskEntry) -> (icon: String, tint: Color) {
        let name = entry.name.lowercased()
        let path = entry.url.path.lowercased()
        func has(_ needle: String) -> Bool { name.contains(needle) || path.contains(needle) }

        if has("node_modules")                       { return ("shippingbox.fill", Color(hex: 0x16A34A)) }
        if has("deriveddata") || has("/developer")   { return ("hammer.fill", .accentPrimary) }
        if has("docker")                             { return ("cube.box.fill", Color(hex: 0x3B82F6)) }
        if name == "pictures" || has(".photoslibrary") || has("photos library") {
            return ("photo.fill", Color(hex: 0xEC4899))
        }
        if name == "downloads"                       { return ("arrow.down.circle.fill", Color(hex: 0xF59E0B)) }
        if name == "music" || has("podcast")         { return ("music.note", Color(hex: 0x8B5CF6)) }
        if name == "movies" || has("video")          { return ("film.fill", Color(hex: 0x3B82F6)) }
        if name == "documents"                       { return ("doc.fill", Color(hex: 0xE0A458)) }
        if name == "desktop"                         { return ("menubar.dock.rectangle", Color(hex: 0x7A746E)) }
        if has("/mail") || name == "mail"            { return ("envelope.fill", Color(hex: 0x14B8A6)) }
        if name == "library"                         { return ("books.vertical.fill", Color(hex: 0x14B8A6)) }
        if has("cache")                              { return ("internaldrive.fill", Color(hex: 0x7A746E)) }
        return ("folder.fill", entry.colorSeed)
    }
}
