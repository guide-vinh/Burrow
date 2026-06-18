import AppKit
import SwiftUI

/// Sidebar shell. Holds the four primary destinations (Clean, Uninstall,
/// Analyze, Status) plus a Settings row at the bottom. Detail area
/// switches manually based on `selection`. We avoid `NavigationView` —
/// its underlying NSSplitViewController re-runs its column-sizing pass
/// when the detail identity changes, which makes the sidebar flicker
/// briefly between tab switches before the `.frame` constraint applies.
struct RootView: View {

    @State private var selection: SidebarDestination = .clean
    @State private var showFDASheet = false

    // Tab view-models are owned here so state survives tab switches.
    // Without this, switching `selection` re-instantiates the destination
    // view's @StateObject and wipes the user's scan / selection.
    @StateObject private var cleanVM = CleanViewModel()
    @StateObject private var uninstallVM = UninstallViewModel()
    @StateObject private var analyzeVM = AnalyzeViewModel()
    @StateObject private var licenseVM = LicenseViewModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .layoutPriority(1)
            Divider()
                .background(Color.borderSubtle)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1200, minHeight: 720)
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
        .frame(width: 220)
        .fixedSize(horizontal: true, vertical: false)
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
        .padding(.horizontal, Spacing.md + Spacing.sm)
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
            SidebarRow(icon: "gear", title: "Settings", isActive: false) {
                openSettings()
            }
            Text("v\(appVersion)")
                .font(.bodyS)
                .foregroundStyle(Color.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md + Spacing.sm)
                .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    /// `CFBundleShortVersionString` from Info.plist; falls back to "—".
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Opens the SwiftUI `Settings` scene. macOS 14 has a first-class
    /// `@Environment(\.openSettings)` for this; macOS 12/13 still need the
    /// AppKit selector route, so use that and stay deployment-target-clean.
    private func openSettings() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .clean:     CleanView(vm: cleanVM)
        case .uninstall: UninstallView(vm: uninstallVM)
        case .analyze:   AnalyzeView(vm: analyzeVM)
        case .licenses:  LicenseView(vm: licenseVM)
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

#Preview("Root — full app") {
    RootView()
        .frame(width: 1200, height: 720)
}

/// Sidebar destinations. Order here is the order shown in the sidebar.
enum SidebarDestination: String, CaseIterable, Hashable {
    case clean
    case uninstall
    case analyze
    case licenses
    case status

    var title: String {
        switch self {
        case .clean:     return "Clean"
        case .uninstall: return "Uninstall"
        case .analyze:   return "Analyze"
        case .licenses:  return "Licenses"
        case .status:    return "Status"
        }
    }

    var icon: String {
        switch self {
        case .clean:     return Iconography.sfSymbol(for: "sparkles")
        case .uninstall: return Iconography.sfSymbol(for: "package-x")
        case .analyze:   return Iconography.sfSymbol(for: "chart-pie")
        case .licenses:  return Iconography.sfSymbol(for: "badge-check")
        case .status:    return Iconography.sfSymbol(for: "activity")
        }
    }
}
