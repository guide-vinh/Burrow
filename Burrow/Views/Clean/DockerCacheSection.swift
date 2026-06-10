import SwiftUI

/// Self-contained Docker reclaim card. Unlike the trash-based sections,
/// `docker … prune` is irreversible, so this card owns its own Reclaim
/// button and confirmation dialog instead of feeding the Move-to-Trash
/// footer. Populated alongside the other scans by the header's Scan.
struct DockerCacheSection: View {
    @ObservedObject var vm: CleanViewModel
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionLabel(text: "Docker (build cache, images, containers)")
            card
        }
    }

    // MARK: - Card

    @ViewBuilder
    private var card: some View {
        if vm.isScanningDockerCache && vm.dockerCacheEntries.isEmpty {
            placeholder(
                spinner: true,
                text: "Asking the Docker daemon what's reclaimable…"
            )
        } else if vm.dockerCacheEntries.isEmpty {
            placeholder(
                spinner: false,
                text: "No reclaimable Docker space found. Click Scan above. (Docker must be installed and running.)"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(vm.dockerCacheEntries) { entry in
                    DockerCacheRow(entry: entry, isSelected: binding(for: entry.kind))
                    if entry.id != vm.dockerCacheEntries.last?.id {
                        Divider().background(Color.borderSubtle)
                    }
                }
                Divider().background(Color.borderSubtle)
                actionRow
            }
            .cardStyle()
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(Color.fgMuted)
            Text("Pruning is permanent — Docker resources are not moved to the Trash.")
                .font(.captionS)
                .foregroundStyle(Color.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.sm)
            if vm.isPruningDocker {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            Group {
                if vm.dryRun {
                    OutlineButton("Preview", icon: "eye") {
                        Task { await vm.pruneSelectedDocker() }
                    }
                } else {
                    DestructiveButton(reclaimButtonTitle, icon: "trash") {
                        confirming = true
                    }
                }
            }
            .disabled(vm.dockerSelection.isEmpty || vm.isPruningDocker || vm.isApplying)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .confirmationDialog(
            "Reclaim \(vm.dockerSelectedBytes, format: .byteCount(style: .file)) of Docker space?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Reclaim now", role: .destructive) {
                Task { await vm.pruneSelectedDocker() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Burrow will run docker prune for the selected items. They will be permanently removed and cannot be restored from the Trash.")
        }
    }

    private var reclaimButtonTitle: String {
        let formatted = vm.dockerSelectedBytes
            .formatted(.byteCount(style: .file))
        return "Reclaim \(formatted)"
    }

    // MARK: - Helpers

    private func binding(for kind: DockerCacheEntry.Kind) -> Binding<Bool> {
        Binding(
            get: { vm.dockerSelection.contains(kind) },
            set: { isOn in
                if isOn { vm.dockerSelection.insert(kind) }
                else    { vm.dockerSelection.remove(kind) }
            }
        )
    }

    private func placeholder(spinner: Bool, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            if spinner {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(Color.fgMuted)
            }
            Text(text)
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .cardStyle()
    }
}

// MARK: - Row

private struct DockerCacheRow: View {
    let entry: DockerCacheEntry
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            BurrowCheckbox(isOn: $isSelected)
                .padding(.top, 2)

            Image(systemName: entry.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.fgSecondary)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                // Line 1 — title + risk pill + count + size
                HStack(spacing: Spacing.sm) {
                    Text(entry.title)
                        .font(.bodyM)
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                    RiskPill(level: entry.risk)
                    if entry.count > 0 {
                        Text("· \(entry.count) \(entry.count == 1 ? "item" : "items")")
                            .font(.bodyS)
                            .foregroundStyle(Color.fgSecondary)
                            .fixedSize()
                    }
                    Spacer(minLength: Spacing.sm)
                    Text(entry.reclaimableBytes, format: .byteCount(style: .file))
                        .font(.bodyS)
                        .foregroundStyle(Color.fgSecondary)
                        .monospacedDigit()
                }

                // Line 2 — summary
                Text(entry.summary)
                    .font(.captionS)
                    .foregroundStyle(Color.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tooltip("\(entry.title)\n\(entry.summary)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
