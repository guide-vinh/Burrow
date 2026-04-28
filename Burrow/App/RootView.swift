import AppKit
import SwiftUI

/// Sidebar shell. Holds the four primary destinations (Clean, Uninstall,
/// Analyze, Status) plus a Settings row at the bottom. Detail area
/// switches manually based on `selection` — `NavigationSplitView` is
/// macOS 13+ so we use the macOS-12-compatible `NavigationView`.
struct RootView: View {

    @State private var selection: SidebarDestination = .clean
    @State private var showFDASheet = false

    var body: some View {
        NavigationView {
            sidebar
            detail
        }
        .navigationViewStyle(.columns)
        .frame(minWidth: 980, minHeight: 640)
        .task { await refreshFDAState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshFDAState() }
        }
        .sheet(isPresented: $showFDASheet) {
            FullDiskAccessSheet(isPresented: $showFDASheet)
        }
    }

    @MainActor
    private func refreshFDAState() async {
        let granted = FullDiskAccess.probe()
        showFDASheet = !granted
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            destinations
            Spacer(minLength: 0)
            settingsFooter
        }
        .frame(minWidth: 220, idealWidth: 220, maxWidth: 220)
        .sidebarStyle()
    }

    private var brandHeader: some View {
        HStack(spacing: Spacing.md) {
            BrandLogo()
            Text("Burrow")
                .font(.titleM)
                .foregroundStyle(Color.fgPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xl)
    }

    private var destinations: some View {
        VStack(spacing: 2) {
            ForEach(SidebarDestination.allCases, id: \.self) { dest in
                SidebarRow(
                    icon: dest.icon,
                    title: dest.title,
                    isActive: selection == dest
                ) {
                    selection = dest
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
    }

    private var settingsFooter: some View {
        VStack(spacing: 0) {
            SidebarRow(icon: "gear", title: "Settings", isActive: false) {}
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .clean:     CleanView()
        case .uninstall: UninstallView()
        case .analyze:   AnalyzeView()
        case .status:    placeholder(for: .status)
        }
    }

    private func placeholder(for destination: SidebarDestination) -> some View {
        EmptyState(
            icon: "hourglass",
            title: "\(destination.title) coming soon",
            subtitle: "This feature lands in a later phase.",
            action: nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }
}

/// Sidebar destinations. Order here is the order shown in the sidebar.
enum SidebarDestination: String, CaseIterable, Hashable {
    case clean
    case uninstall
    case analyze
    case status

    var title: String {
        switch self {
        case .clean:     return "Clean"
        case .uninstall: return "Uninstall"
        case .analyze:   return "Analyze"
        case .status:    return "Status"
        }
    }

    var icon: String {
        switch self {
        case .clean:     return Iconography.sfSymbol(for: "sparkles")
        case .uninstall: return Iconography.sfSymbol(for: "package-x")
        case .analyze:   return Iconography.sfSymbol(for: "chart-pie")
        case .status:    return Iconography.sfSymbol(for: "activity")
        }
    }
}
