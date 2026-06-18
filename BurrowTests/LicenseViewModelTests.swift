import XCTest
@testable import Burrow

@MainActor
final class LicenseViewModelTests: XCTestCase {

    // MARK: - Builders

    private func app(_ bundleId: String, _ name: String,
                     source: InstallSource = .manual) -> InstalledApp {
        InstalledApp(
            bundleId: bundleId, name: name, displayName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            version: "1.0", build: "1", bundleSize: nil,
            lastOpenedDate: nil, installSource: source
        )
    }

    private func sig(valid: Bool = true, unsigned: Bool = false, adHoc: Bool = false,
                     apple: Bool = false, developer: String? = nil) -> SignatureInfo {
        SignatureInfo(isValid: valid, isUnsigned: unsigned, isAdHoc: adHoc,
                      isApple: apple, isNotarized: nil, developer: developer, teamID: nil)
    }

    private func makeVM(apps: [InstalledApp], sigs: [URL: SignatureInfo],
                        stores: [String: StoreInfo] = [:], online: Bool = false) -> LicenseViewModel {
        let vm = LicenseViewModel(
            discoverApps: { apps },
            inspectSignature: { sigs[$0] ?? .unknown },
            lookupStore: { stores[$0] }
        )
        vm.onlineLookupsEnabled = online
        return vm
    }

    // MARK: - Verdict mapping

    func testVerdictMapping() {
        let manual = app("com.x", "X")
        let mas = app("com.y", "Y", source: .macAppStore)

        XCTAssertEqual(LicenseViewModel.makeVerdict(app: manual, signature: sig(valid: false, unsigned: true), store: nil).0, .unverified)
        XCTAssertEqual(LicenseViewModel.makeVerdict(app: manual, signature: sig(valid: false), store: nil).0, .unverified)
        XCTAssertEqual(LicenseViewModel.makeVerdict(app: manual, signature: sig(adHoc: true), store: nil).0, .unverified)
        XCTAssertEqual(LicenseViewModel.makeVerdict(app: mas, signature: sig(), store: nil).0, .appStore)
        XCTAssertEqual(LicenseViewModel.makeVerdict(app: manual, signature: sig(apple: true), store: nil).0, .verifiedDeveloper)
        XCTAssertEqual(LicenseViewModel.makeVerdict(app: manual, signature: sig(developer: "Acme"), store: nil).0, .verifiedDeveloper)
        XCTAssertEqual(LicenseViewModel.makeVerdict(app: manual, signature: sig(developer: nil), store: nil).0, .unknown)
    }

    func testAdHocAppleIsNotFlagged() {
        // Some Apple binaries are ad-hoc but Apple-anchored — must not be flagged.
        let v = LicenseViewModel.makeVerdict(app: app("com.apple.x", "X"), signature: sig(adHoc: true, apple: true), store: nil)
        XCTAssertEqual(v.0, .verifiedDeveloper)
    }

    // MARK: - Scan + counts

    func testScanPopulatesAndCounts() async {
        let a = app("com.a", "Acme", source: .manual)
        let b = app("com.b", "Bee", source: .macAppStore)
        let c = app("com.c", "Crack", source: .manual)
        let vm = makeVM(
            apps: [a, b, c],
            sigs: [
                a.bundleURL: sig(developer: "Acme Inc"),
                b.bundleURL: sig(),
                c.bundleURL: sig(valid: false),   // tampered
            ]
        )
        await vm.scan()

        XCTAssertFalse(vm.isScanning)
        XCTAssertEqual(vm.licenses.count, 3)
        XCTAssertEqual(vm.count(for: .all), 3)
        XCTAssertEqual(vm.count(for: .appStore), 1)
        XCTAssertEqual(vm.count(for: .verified), 1)
        XCTAssertEqual(vm.count(for: .unverified), 1)
        XCTAssertEqual(vm.unverifiedCount, 1)
        // Unverified sorts first.
        XCTAssertEqual(vm.filteredLicenses.first?.verdict, .unverified)
    }

    // MARK: - Online annotation

    func testOnlineLookupAnnotatesPrice() async {
        let b = app("com.b", "Bee", source: .macAppStore)
        let vm = makeVM(
            apps: [b],
            sigs: [b.bundleURL: sig()],
            stores: ["com.b": StoreInfo(price: 0, isFree: true, sellerName: "Bee Co", listingURL: nil)],
            online: true
        )
        await vm.scan()

        let license = vm.licenses.first
        XCTAssertEqual(license?.store?.isFree, true)
        XCTAssertTrue(license?.reason.contains("Free") == true, "price folded into reason")
    }

    func testOnlineDisabledLeavesStoreNil() async {
        let b = app("com.b", "Bee", source: .macAppStore)
        let vm = makeVM(
            apps: [b], sigs: [b.bundleURL: sig()],
            stores: ["com.b": StoreInfo(price: 5, isFree: false, sellerName: "Bee Co", listingURL: nil)],
            online: false
        )
        await vm.scan()
        XCTAssertNil(vm.licenses.first?.store)
    }

    // MARK: - CSV export

    func testCSVReportHasHeaderAndRows() async {
        let a = app("com.a", "Acme")
        let vm = makeVM(apps: [a], sigs: [a.bundleURL: sig(developer: "Acme Inc")])
        await vm.scan()

        let csv = vm.csvReport()
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "header + one app")
        XCTAssertTrue(lines[0].hasPrefix("\"Name\",\"Bundle ID\""))
        XCTAssertTrue(lines[1].contains("\"Acme\""))
        XCTAssertTrue(lines[1].contains("\"Verified\""))
    }
}
