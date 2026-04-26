import SwiftUI

/// Bottom zone of the Clean tab: selection summary on the left,
/// Move-to-Trash (or Preview, in dry-run mode) on the right. Button
/// is disabled until at least one selected category has scan results.
struct CleanFooter: View {
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                if !vm.scanResults.isEmpty {
                    Text("\(vm.selectedItemCount) items selected · \(vm.selectedTotalBytes, format: .byteCount(style: .file))")
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                        .monospacedDigit()
                }
                if let preview = vm.lastPreview {
                    Text("Last preview: \(preview.items) items · \(preview.bytes, format: .byteCount(style: .file))")
                        .font(.captionS)
                        .foregroundStyle(Color.fgMuted)
                        .monospacedDigit()
                }
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

    private func applyAction() {
        Task { await vm.apply() }
    }
}
