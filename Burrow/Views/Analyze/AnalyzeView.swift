import SwiftUI

/// Top-level view for the Analyze tab. Three states: empty (Scan home),
/// scanning (progress + cancel), and scanned — a storage dashboard with a
/// donut + capacity summary (left) and a largest-folders list (right).
struct AnalyzeView: View {

    @ObservedObject var vm: AnalyzeViewModel

    var body: some View {
        Group {
            if vm.hasResults {
                // Dashboard appears as soon as capacity is known; folders
                // stream in while the scan continues.
                scannedState
            } else if vm.isScanning {
                scanningState
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            if let error = vm.scanError {
                errorBanner(error)
            }
            EmptyState(
                icon: "chart.pie",
                title: "Scan your home folder",
                subtitle: "See where your disk space goes — by category and by folder.",
                action: ("Scan home", { Task { await vm.scan() } })
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.destructive)
            Text(message)
                .font(.bodyS)
                .foregroundStyle(Color.destructive)
                .lineLimit(2)
            Spacer(minLength: 0)
            OutlineButton("Try again") {
                Task { await vm.scan() }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.Risk.highBG)
    }

    // MARK: - Scanning state

    private var scanningState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
            Text("Scanning…")
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
            OutlineButton("Cancel") {
                vm.cancelScan()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    // MARK: - Scanned state

    private var scannedState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                columns
            }
            .padding(.horizontal, Spacing.xxl + Spacing.sm)
            .padding(.vertical, Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Analyze")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fgPrimary)
                Text("Storage breakdown for \(vm.storage?.volumeName ?? "this Mac")")
                    .font(.bodyM)
                    .foregroundStyle(Color.fgSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if vm.isScanning {
                HStack(spacing: Spacing.xs + 2) {
                    ProgressView().controlSize(.small)
                    Text(scanningLabel)
                        .font(.captionM)
                        .foregroundStyle(Color.fgSecondary)
                }
                .padding(.trailing, Spacing.xs)
            }
            OutlineButton("Rescan") {
                Task { await vm.scan() }
            }
        }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            leftColumn.frame(width: 340)
            LargestFoldersList(vm: vm)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var leftColumn: some View {
        if let storage = vm.storage {
            VStack(spacing: Spacing.lg + 4) {
                StorageCard(breakdown: storage)
                CapacitySummaryCard(breakdown: storage)
            }
        }
    }

    private var scanningLabel: String {
        vm.totalTopLevel > 0
            ? "Scanning \(vm.foldersScanned)/\(vm.totalTopLevel)"
            : "Scanning…"
    }
}

// No #Preview: AnalyzeViewModel triggers a real scan; preview the
// constituent views (DonutChart, StorageCard, …) directly.
