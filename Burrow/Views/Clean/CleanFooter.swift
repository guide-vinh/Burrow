import SwiftUI

/// Bottom zone of the Clean tab: selection summary on the left,
/// Move-to-Trash (or Preview, in dry-run mode) on the right. Button
/// is disabled until at least one selected category has scan results.
struct CleanFooter: View {
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            if !vm.scanResults.isEmpty {
                Text(selectionSummary)
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                    .monospacedDigit()
            }
            Spacer()
            Group {
                if vm.dryRun {
                    OutlineButton("Preview", icon: "eye", action: applyAction)
                } else {
                    DestructiveButton("Move to Trash", icon: "trash", action: applyAction)
                }
            }
            .disabled(vm.selectedItemCount == 0 || vm.isApplying)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }

    private var selectionSummary: String {
        let cats = vm.selectedCategoryCount
        let paths = vm.selectedItemCount
        let bytes = vm.selectedTotalBytes
            .formatted(.byteCount(style: .file))
        let catWord = cats == 1 ? "category" : "categories"
        let pathWord = paths == 1 ? "path" : "paths"
        return "\(cats) \(catWord) · \(paths) \(pathWord) · \(bytes)"
    }

    private func applyAction() {
        Task { await vm.apply() }
    }
}
