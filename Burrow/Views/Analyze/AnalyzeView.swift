import SwiftUI

/// Top-level view for the Analyze tab.
/// Composes TreemapCanvas, InsightsPanel, and Breadcrumb into a three-state
/// layout backed by AnalyzeViewModel.
struct AnalyzeView: View {

    @StateObject private var vm = AnalyzeViewModel()

    /// Tracks the body area width for responsive layout switching.
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        Group {
            if vm.isScanning {
                scanningState
            } else if let root = vm.currentRoot, !vm.isScanning {
                // Scanned: root is available
                let _ = root // suppress unused warning
                scannedState
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            if let error = vm.scanError {
                errorBanner(error)
            }
            EmptyState(
                icon: "chart.pie",
                title: "Scan your home folder",
                subtitle: "Find what's eating your disk — caches, old downloads, library cruft.",
                action: ("Scan home", { Task { await vm.scan() } })
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.destructive)
            Text(message)
                .font(.bodyS)
                .foregroundStyle(Color.destructive)
                .lineLimit(2)
            Spacer(minLength: 0)
            OutlineButton("Try again") {
                Task { await vm.scan() }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.Risk.highBG)
    }

    // MARK: - Scanning state

    private var scanningState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
            Text(scanProgressLine)
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
            if let currentPath = vm.scanProgress?.currentPath {
                Text(abbreviatedPath(currentPath))
                    .font(.monoS)
                    .foregroundStyle(Color.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            OutlineButton("Cancel") {
                vm.cancelScan()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    private var scanProgressLine: String {
        guard let progress = vm.scanProgress else { return "Scanning…" }
        let entries = progress.entriesScanned.formatted()
        let bytes = humanBytes(progress.totalBytes)
        return "\(entries) entries · \(bytes)"
    }

    // MARK: - Scanned state

    private var scannedState: some View {
        VStack(spacing: 0) {
            scannedHeader
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            Divider()
                .background(Color.borderSubtle)
            scannedBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    // MARK: Header

    private var scannedHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Row 1: breadcrumb + rescan
            HStack {
                Breadcrumb(
                    path: vm.breadcrumb,
                    onNavigate: { url in Task { await vm.navigate(to: url) } }
                )
                Spacer(minLength: Spacing.sm)
                OutlineButton("Rescan") {
                    Task { await vm.scan() }
                }
            }
            // Row 2: stats
            Text(statsLine)
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
        }
    }

    private var statsLine: String {
        if let progress = vm.scanProgress {
            let bytes = humanBytes(progress.totalBytes)
            let entries = progress.entriesScanned.formatted()
            return "\(bytes) used · \(entries) entries"
        }
        return "\(vm.visibleEntries.count) entries shown"
    }

    // MARK: Body (treemap + insights, responsive)

    private var scannedBody: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Group {
                if width < 900 {
                    VStack(spacing: 0) {
                        treemapView
                            .frame(maxWidth: .infinity, minHeight: 320)
                            .padding(Spacing.lg)
                        Divider()
                            .background(Color.borderSubtle)
                        insightsPanelView
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(spacing: 0) {
                        treemapView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(Spacing.lg)
                        Divider()
                            .background(Color.borderSubtle)
                        insightsPanelView
                            .frame(width: 320)
                    }
                }
            }
            .onChange(of: width) { newWidth in
                containerWidth = newWidth
            }
            .onAppear {
                containerWidth = width
            }
        }
    }

    private var treemapView: some View {
        TreemapCanvas(
            entries: vm.visibleEntries,
            onTap: { entry in
                Task { await vm.zoomInto(entry) }
            },
            onContextMenu: { entry, action in
                switch action {
                case .revealInFinder:
                    vm.revealInFinder(entry)
                case .moveToTrash:
                    Task { await vm.moveToTrash(entry) }
                }
            }
        )
    }

    private var insightsPanelView: some View {
        InsightsPanel(
            topLargest: vm.topLargest,
            oldestNeverOpened: vm.oldestNeverOpened,
            onRevealInFinder: { entry in vm.revealInFinder(entry) }
        )
    }
}

// MARK: - Private helpers

private func humanBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

private func abbreviatedPath(_ url: URL, maxChars: Int = 60) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path + "/"
    var s = url.path
    if s.hasPrefix(home) { s = "~/" + String(s.dropFirst(home.count)) }
    if s.count > maxChars {
        let head = s.prefix(maxChars / 2 - 1)
        let tail = s.suffix(maxChars / 2 - 2)
        s = "\(head)…\(tail)"
    }
    return s
}

// No #Preview: AnalyzeViewModel triggers a real scan; preview the constituent views (TreemapCanvas, InsightsPanel, Breadcrumb) directly.
