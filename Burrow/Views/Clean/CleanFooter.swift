import SwiftUI

/// Bottom zone of the Clean tab: selection summary on the left,
/// Move-to-Trash button on the right. Button is disabled until at
/// least one selected category has scan results.
struct CleanFooter: View {
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            if !vm.scanResults.isEmpty {
                Text("\(vm.selectedItemCount) items selected · \(vm.selectedTotalBytes, format: .byteCount(style: .file))")
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                    .monospacedDigit()
            }
            Spacer()
            DestructiveButton("Move to Trash", icon: "trash") {
                Task { await vm.apply() }
            }
            .disabled(vm.selectedItemCount == 0 || vm.isApplying)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }
}
