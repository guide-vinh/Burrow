import SwiftUI

/// Bottom zone of the Clean tab: selection summary on the left,
/// Move-to-Trash + Delete (or Preview, in dry-run mode) on the right.
/// Buttons are disabled until at least one selected category has scan
/// results. Delete bypasses the Trash and always confirms first.
struct CleanFooter: View {
    @ObservedObject var vm: CleanViewModel
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            if !vm.scanResults.isEmpty || !vm.nodeModulesEntries.isEmpty || !vm.flutterProjects.isEmpty {
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
                    DestructiveButton("Delete", icon: "trash.slash") {
                        showDeleteConfirm = true
                    }
                }
            }
            .disabled(!vm.hasAnySelection || vm.isApplying)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .alert("Delete permanently?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await vm.applyAll(permanently: true) }
            }
        } message: {
            Text(deleteConfirmMessage)
        }
    }

    private var deleteConfirmMessage: String {
        let paths = vm.combinedSelectedItemCount
        let word = paths == 1 ? "path" : "paths"
        let bytes = vm.combinedSelectedBytes.formatted(.byteCount(style: .file))
        return "\(paths) \(word) (\(bytes)) will be deleted immediately, bypassing the Trash. This cannot be undone."
    }

    private var selectionSummary: String {
        let cats = vm.selectedCategoryCount
        let nm = vm.nodeModulesSelection.count
        let fl = vm.flutterSelection.count
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
        if fl > 0 {
            parts.append("\(fl) Flutter")
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
