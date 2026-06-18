import SwiftUI

/// Top-level view for the Licenses tab. Lists every installed app with a
/// compliance verdict (App Store / Verified / Unverified / Unknown), filters
/// with counts, and a CSV export. Three states: empty, scanning, scanned.
struct LicenseView: View {

    @ObservedObject var vm: LicenseViewModel

    var body: some View {
        Group {
            if vm.hasResults {
                scannedState
            } else if vm.isScanning {
                scanningState
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 0) {
            if let error = vm.scanError { errorBanner(error) }
            EmptyState(
                icon: "checkmark.seal",
                title: "Check your app licenses",
                subtitle: "See which apps are App Store, signed by a known developer, or unverified (possibly modified).",
                action: ("Scan apps", { Task { await vm.scan() } })
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.destructive)
            Text(message).font(.bodyS).foregroundStyle(Color.destructive).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.Risk.highBG)
    }

    // MARK: - Scanning

    private var scanningState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
            Text("Inspecting apps…").font(.bodyS).foregroundStyle(Color.fgSecondary)
            OutlineButton("Cancel") { vm.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    // MARK: - Scanned

    private var scannedState: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            filterBar
            ScrollView {
                VStack(spacing: Spacing.sm + 2) {
                    ForEach(vm.filteredLicenses) { license in
                        LicenseRow(
                            license: license,
                            onReveal: { vm.revealInFinder(license) },
                            onOpenStore: { vm.openStoreListing(license) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.xxl + Spacing.sm)
        .padding(.vertical, Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfacePrimary)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Licenses")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fgPrimary)
                Text(summary)
                    .font(.bodyM)
                    .foregroundStyle(vm.unverifiedCount > 0 ? Color.destructive : Color.fgSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if vm.isScanning {
                ProgressView().controlSize(.small).padding(.trailing, Spacing.xs)
            }
            OutlineButton("Export") { vm.exportReport() }
            OutlineButton("Rescan") { Task { await vm.scan() } }
        }
    }

    private var summary: String {
        let total = vm.licenses.count
        if vm.unverifiedCount > 0 {
            return "\(vm.unverifiedCount) of \(total) apps need review"
        }
        return "\(total) apps checked"
    }

    private var filterBar: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(LicenseViewModel.Filter.allCases) { f in
                let selected = vm.filter == f
                Button { vm.filter = f } label: {
                    HStack(spacing: Spacing.xs + 2) {
                        Text(f.label).font(.captionM.weight(.medium))
                        Text("\(vm.count(for: f))")
                            .font(.captionS)
                            .foregroundStyle(selected ? Color.accentPrimary : Color.fgMuted)
                    }
                    .foregroundStyle(selected ? Color.accentPrimary : Color.fgSecondary)
                    .padding(.horizontal, Spacing.md - 2)
                    .padding(.vertical, Spacing.sm - 2)
                    .background(
                        Capsule().fill(selected ? Color.accentSoft : Color.surfaceSecondary)
                    )
                    .overlay(Capsule().stroke(Color.borderSubtle, lineWidth: selected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
