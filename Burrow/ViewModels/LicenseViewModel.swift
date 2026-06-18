import AppKit               // NSSavePanel, NSWorkspace
import Foundation
import SwiftUI               // ObservableObject + @Published only
import os

private let logger = Logger(subsystem: "fun.burrow", category: "LicenseViewModel")

/// Drives the Licenses tab. Enumerates installed apps, inspects each app's
/// code signature (streamed in live), optionally confirms App Store listings
/// online, and derives a compliance verdict per app. Exports a CSV report.
/// Pure data; views map data → visuals.
@MainActor
final class LicenseViewModel: ObservableObject {

    // MARK: - Filter

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case appStore
        case verified
        case unverified
        case unknown

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:        return "All"
            case .appStore:   return "App Store"
            case .verified:   return "Verified"
            case .unverified: return "Unverified"
            case .unknown:    return "Unknown"
            }
        }
    }

    // MARK: - State

    @Published private(set) var isScanning = false
    @Published private(set) var scanError: String?
    @Published private(set) var licenses: [AppLicense] = []
    @Published var filter: Filter = .all
    @Published var onlineLookupsEnabled = true

    var hasResults: Bool { !licenses.isEmpty }

    /// Licenses for the active filter, unverified first, then by name.
    var filteredLicenses: [AppLicense] {
        let matching = licenses.filter { matches(filter, $0.verdict) }
        return matching.sorted { lhs, rhs in
            if lhs.verdict.sortRank != rhs.verdict.sortRank {
                return lhs.verdict.sortRank < rhs.verdict.sortRank
            }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }
    }

    func count(for filter: Filter) -> Int {
        licenses.filter { matches(filter, $0.verdict) }.count
    }

    /// Apps flagged for review (the headline compliance number).
    var unverifiedCount: Int { licenses.filter { $0.verdict == .unverified }.count }

    // MARK: - Dependencies

    private let discoverApps: @Sendable () async -> [InstalledApp]
    private let inspectSignature: @Sendable (URL) -> SignatureInfo
    private let lookupStore: @Sendable (String) async -> StoreInfo?

    private var scanTask: Task<Void, Never>?

    init(
        discoverApps: @escaping @Sendable () async -> [InstalledApp]
            = { await AppScanner.shared.discoverInstalledApps() },
        inspectSignature: @escaping @Sendable (URL) -> SignatureInfo
            = { CodeSignInspector.inspect($0) },
        lookupStore: @escaping @Sendable (String) async -> StoreInfo?
            = { await AppStoreLookup.lookup(bundleId: $0) }
    ) {
        self.discoverApps = discoverApps
        self.inspectSignature = inspectSignature
        self.lookupStore = lookupStore
    }

    // MARK: - Scan

    func scan() async {
        cancelScan()
        isScanning = true
        scanError = nil
        licenses = []

        let inspect = inspectSignature
        let discover = discoverApps
        let online = onlineLookupsEnabled
        let lookup = lookupStore

        scanTask = Task { [weak self] in
            guard let self else { return }
            let apps = await discover()

            // Phase 1 — inspect signatures in parallel, stream rows in.
            let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount)
            await withTaskGroup(of: (InstalledApp, SignatureInfo).self) { group in
                var queue = apps
                for _ in 0..<min(maxConcurrent, queue.count) {
                    let app = queue.removeLast()
                    group.addTask { (app, inspect(app.bundleURL)) }
                }
                while let (app, signature) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }
                    let (verdict, reason) = Self.makeVerdict(app: app, signature: signature, store: nil)
                    self.licenses.append(AppLicense(
                        app: app, signature: signature, store: nil, verdict: verdict, reason: reason
                    ))
                    if let next = queue.popLast() {
                        group.addTask { (next, inspect(next.bundleURL)) }
                    }
                }
            }

            // Signatures done — results are usable now; stop the spinner and
            // let online price lookups fill in afterward.
            if !Task.isCancelled { self.isScanning = false }

            // Phase 2 — confirm App Store listings / prices online (opted in).
            if online && !Task.isCancelled {
                let bundleIds = self.licenses.map(\.app.bundleId)
                await withTaskGroup(of: (String, StoreInfo?).self) { group in
                    var queue = bundleIds
                    let cap = 6
                    for _ in 0..<min(cap, queue.count) {
                        let id = queue.removeLast()
                        group.addTask { (id, await lookup(id)) }
                    }
                    while let (id, store) = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        if let store { self.annotate(bundleId: id, store: store) }
                        if let next = queue.popLast() {
                            group.addTask { (next, await lookup(next)) }
                        }
                    }
                }
            }

            self.isScanning = false
            logger.info("License scan finished: \(self.licenses.count, privacy: .public) apps, \(self.unverifiedCount, privacy: .public) unverified")
        }

        await scanTask?.value
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: - Actions

    func revealInFinder(_ license: AppLicense) {
        NSWorkspace.shared.activateFileViewerSelecting([license.app.bundleURL])
    }

    func openStoreListing(_ license: AppLicense) {
        if let url = license.store?.listingURL { NSWorkspace.shared.open(url) }
    }

    /// Write a CSV compliance report via a save panel.
    func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Burrow-License-Report.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csvReport().write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            scanError = "Couldn't write report: \(error.localizedDescription)"
        }
    }

    /// CSV string for the current scan. Internal for tests.
    func csvReport() -> String {
        let header = ["Name", "Bundle ID", "Version", "Source", "Developer",
                      "Signature", "Ad-hoc", "Price", "Verdict"]
        var lines = [header.map(Self.csvField).joined(separator: ",")]
        for l in filteredLicenses {
            let row = [
                l.app.name,
                l.app.bundleId,
                l.app.version ?? "",
                l.app.installSource.rawValue,
                l.signature.developer ?? "",
                l.signature.isUnsigned ? "unsigned" : (l.signature.isValid ? "valid" : "invalid"),
                l.signature.isAdHoc ? "yes" : "no",
                l.store?.priceLabel ?? "",
                l.verdict.title,
            ]
            lines.append(row.map(Self.csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func annotate(bundleId: String, store: StoreInfo) {
        guard let idx = licenses.firstIndex(where: { $0.app.bundleId == bundleId }) else { return }
        licenses[idx].store = store
        let (verdict, reason) = Self.makeVerdict(
            app: licenses[idx].app, signature: licenses[idx].signature, store: store
        )
        licenses[idx].verdict = verdict
        licenses[idx].reason = reason
    }

    private func matches(_ filter: Filter, _ verdict: LicenseVerdict) -> Bool {
        switch filter {
        case .all:        return true
        case .appStore:   return verdict == .appStore
        case .verified:   return verdict == .verifiedDeveloper
        case .unverified: return verdict == .unverified
        case .unknown:    return verdict == .unknown
        }
    }

    /// Derive verdict + reason from signature facts and (optional) store info.
    static func makeVerdict(
        app: InstalledApp, signature sig: SignatureInfo, store: StoreInfo?
    ) -> (LicenseVerdict, String) {
        if sig.isUnsigned {
            return (.unverified, "No code signature")
        }
        if !sig.isValid {
            return (.unverified, "Signature invalid — bundle modified")
        }
        if sig.isAdHoc && !sig.isApple {
            return (.unverified, "Ad-hoc signature — not from a known developer")
        }
        let priceSuffix = store.map { " · \($0.priceLabel)" } ?? ""
        if app.installSource == .macAppStore {
            return (.appStore, "Mac App Store\(priceSuffix)")
        }
        if sig.isApple {
            return (.verifiedDeveloper, "Apple system software")
        }
        if let developer = sig.developer {
            return (.verifiedDeveloper, "Signed by \(developer)\(priceSuffix)")
        }
        return (.unknown, "Signed, but developer could not be determined")
    }

    private static func csvField(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private extension LicenseVerdict {
    /// Lower sorts first — flag problems at the top.
    var sortRank: Int {
        switch self {
        case .unverified: return 0
        case .unknown:    return 1
        case .verifiedDeveloper: return 2
        case .appStore:   return 3
        }
    }
}
