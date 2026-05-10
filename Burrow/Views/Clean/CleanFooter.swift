import SwiftUI

/// Bottom zone of the Clean tab: selection summary on the left,
/// Move-to-Trash (or Preview, in dry-run mode) on the right. Button
/// is disabled until at least one selected category has scan results.
struct CleanFooter: View {
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            if !vm.scanResults.isEmpty || !vm.nodeModulesEntries.isEmpty {
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
            .disabled(!vm.hasAnySelection || vm.isApplying)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }

    private var selectionSummary: String {
        let cats = vm.selectedCategoryCount
        let nm = vm.nodeModulesSelection.count
        let paths = vm.combinedSelectedItemCount
        let bytes = vm.combinedSelectedBytes
            .formatted(.byteCount(style: .file))

        var parts: [String] = []
        if cats > 0 {
            parts.append("\(cats) \(cats == 1 ? "category" : "categories")")
        }
        if nm > 0 {
            parts.append("\(nm) node_modules")
        }
        let pathWord = paths == 1 ? "path" : "paths"
        parts.append("\(paths) \(pathWord)")
        parts.append(bytes)
        return parts.joined(separator: " · ")
    }

    private func applyAction() {
        Task { await vm.applyAll() }
    }
}
