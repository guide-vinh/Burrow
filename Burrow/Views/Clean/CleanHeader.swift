import SwiftUI

/// Top zone of the Clean tab: title + reclaim subtitle on the left,
/// dry-run toggle + Scan button on the right.
struct CleanHeader: View {
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clean")
                    .font(.titleL)
                    .foregroundStyle(Color.fgPrimary)
                if vm.totalReclaimable > 0 {
                    Text("Found \(vm.totalReclaimable, format: .byteCount(style: .file)) reclaimable")
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                }
            }

            Spacer(minLength: Spacing.md)

            HStack(spacing: Spacing.sm) {
                BurrowCheckbox(isOn: Binding(
                    get: { vm.allCategoriesSelected },
                    set: { _ in vm.toggleSelectAll() }
                ))
                Text("Select all")
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                    .onTapGesture { vm.toggleSelectAll() }
            }
            .disabled(vm.categories.isEmpty)

            HStack(spacing: Spacing.sm) {
                Text("Dry run")
                    .font(.bodyS)
                    .foregroundStyle(Color.fgSecondary)
                BurrowToggle(isOn: $vm.dryRun)
            }

            PrimaryButton("Scan") {
                Task { await vm.scan() }
            }
            .disabled(vm.isScanning || vm.categories.isEmpty)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }
}
