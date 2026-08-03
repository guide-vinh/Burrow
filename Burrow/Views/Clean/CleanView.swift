import AppKit
import SwiftUI

/// The Clean tab. Three vertical zones (header / scrolling body /
/// footer) per SPEC section 8. Owns the view-model via @StateObject;
/// children receive it via @ObservedObject.
struct CleanView: View {
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        VStack(spacing: 0) {
            CleanHeader(vm: vm)
            Divider().background(Color.borderSubtle)

            if let summary = vm.previewBanner {
                PreviewBanner(
                    summary: summary,
                    actionTitle: "View Log",
                    onAction: openLog,
                    onDismiss: { vm.dismissPreviewBanner() }
                )
                Divider().background(Color.borderSubtle)
            }

            ScrollView {
                // Manual two-column layout (replaces LazyVGrid) so the
                // project caches sections can sit under the short right
                // column instead of below the long developer list.
                HStack(alignment: .top, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        ForEach(leftColumn, id: \.group) { entry in
                            CategoryGroupSection(
                                group: entry.group,
                                categories: entry.categories,
                                vm: vm
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        ForEach(rightColumn, id: \.group) { entry in
                            CategoryGroupSection(
                                group: entry.group,
                                categories: entry.categories,
                                vm: vm
                            )
                        }
                        NodeModulesSection(vm: vm)
                        FlutterProjectSection(vm: vm)
                        DockerCacheSection(vm: vm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.borderSubtle)
            CleanFooter(vm: vm)
        }
        .background(Color.surfacePrimary)
        .task { await vm.loadCatalog() }
    }

    /// Even-indexed groups in `categoriesByGroup` — preserves the prior
    /// row-major LazyVGrid mapping so existing groups stay where users
    /// expect them.
    private var leftColumn: [(group: CategoryGroup, categories: [CleanCategory])] {
        vm.categoriesByGroup.enumerated().compactMap { idx, entry in
            idx % 2 == 0 ? entry : nil
        }
    }

    /// Odd-indexed groups — the project caches sections are appended
    /// after these so they sit directly below the (typically short)
    /// SYSTEM JUNK card for visibility.
    private var rightColumn: [(group: CategoryGroup, categories: [CleanCategory])] {
        vm.categoriesByGroup.enumerated().compactMap { idx, entry in
            idx % 2 == 1 ? entry : nil
        }
    }

    /// Open today's operations log with the user's default .log viewer.
    /// Falls back to revealing the logs folder in Finder if today's
    /// file doesn't exist (e.g. every append in the run failed).
    private func openLog() {
        let url = vm.operationsLogURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }
}
