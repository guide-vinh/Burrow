import AppKit
import SwiftUI

/// The Clean tab. Three vertical zones (header / scrolling body /
/// footer) per SPEC section 8. Owns the view-model via @StateObject;
/// children receive it via @ObservedObject.
struct CleanView: View {
    @StateObject private var vm = CleanViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xl, alignment: .top),
        GridItem(.flexible(), spacing: Spacing.xl, alignment: .top),
    ]

    var body: some View {
        VStack(spacing: 0) {
            CleanHeader(vm: vm)
            Divider().background(Color.borderSubtle)

            if let summary = vm.previewBanner {
                PreviewBanner(
                    summary: summary,
                    onShowInFinder: revealLog,
                    onDismiss: { vm.dismissPreviewBanner() }
                )
                Divider().background(Color.borderSubtle)
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.xl) {
                    ForEach(vm.categoriesByGroup, id: \.group) { entry in
                        CategoryGroupSection(
                            group: entry.group,
                            categories: entry.categories,
                            vm: vm
                        )
                    }
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

    /// Reveal the operations log in Finder so the user can open it
    /// with whichever app they prefer (TextEdit, BBEdit, VS Code, …).
    private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([vm.operationsLogURL])
    }
}
