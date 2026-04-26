import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Uninstall tab. Two-column split view (app list left, detail
/// right). Accepts dropped .app bundles from Finder; resolves the URL
/// against the discovered apps list and selects the match.
struct UninstallView: View {
    @StateObject private var vm = UninstallViewModel()
    @State private var isDropping = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            UninstallDetail(vm: vm)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.surfacePrimary)
        .overlay(dropTargetOverlay)
        .onDrop(of: [.fileURL], isTargeted: $isDropping, perform: handleDrop)
        .task { await vm.loadApps() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            Divider().background(Color.borderSubtle)
            appList
        }
        .background(Color.surfaceSecondary)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.fgMuted)
            TextField("Search apps", text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .font(.bodyS)
                .foregroundStyle(Color.fgPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm + 2)
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(vm.filteredApps) { app in
                    AppListRow(
                        app: app,
                        isActive: vm.selectedApp?.bundleId == app.bundleId
                    ) {
                        Task { await vm.select(app) }
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Drag-drop

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropping {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.accentPrimary, lineWidth: 2)
                .background(
                    Color.accentSoft.opacity(0.4)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                )
                .padding(Spacing.md)
                .allowsHitTesting(false)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "app" else { return }
                Task { @MainActor in
                    let standardized = url.standardizedFileURL
                    if let app = vm.apps.first(where: {
                        $0.bundleURL.standardizedFileURL == standardized
                    }) {
                        await vm.select(app)
                    }
                    // else: silently ignore — Phase 2 v0.1 only handles
                    // apps already in the discovered list.
                }
            }
            return true
        }
        return false
    }
}
