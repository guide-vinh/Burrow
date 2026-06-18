import Foundation
import SwiftUI

/// Code-signature facts for an app bundle, from `CodeSignInspector`.
/// Pure value type — `Sendable` so it can cross the scan's task boundaries.
struct SignatureInfo: Sendable, Hashable {
    /// Signature present and the bundle verifies (not tampered).
    var isValid: Bool
    /// No code signature at all.
    var isUnsigned: Bool
    /// Ad-hoc signed (signed locally with no identity — typical of re-signed cracks).
    var isAdHoc: Bool
    /// Signed by Apple itself (system software).
    var isApple: Bool
    /// Passes Gatekeeper / notarization. `nil` when it couldn't be assessed.
    var isNotarized: Bool?
    /// Human-readable signing identity (e.g. "Google LLC"), if any.
    var developer: String?
    /// Apple Developer Team ID, if present.
    var teamID: String?

    static let unknown = SignatureInfo(
        isValid: false, isUnsigned: false, isAdHoc: false,
        isApple: false, isNotarized: nil, developer: nil, teamID: nil
    )
}

/// App Store listing facts from `AppStoreLookup` (the opted-in online step).
struct StoreInfo: Sendable, Hashable {
    var price: Decimal?
    var isFree: Bool
    var sellerName: String?
    var listingURL: URL?

    var priceLabel: String {
        if isFree { return "Free" }
        if let price, price > 0 {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.locale = Locale(identifier: "en_US")
            return f.string(from: price as NSDecimalNumber) ?? "Paid"
        }
        return "Paid"
    }
}

/// Compliance verdict for an installed app. The UI never asserts "cracked";
/// `.unverified` means the signature is broken/ad-hoc — the practical signal.
enum LicenseVerdict: String, Sendable, CaseIterable {
    case appStore
    case verifiedDeveloper
    case unverified
    case unknown

    var title: String {
        switch self {
        case .appStore:          return "App Store"
        case .verifiedDeveloper: return "Verified"
        case .unverified:        return "Unverified"
        case .unknown:           return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .appStore:          return Color(hex: 0x2E7D32)   // green
        case .verifiedDeveloper: return Color(hex: 0x2E7D32)   // green
        case .unverified:        return Color(hex: 0xB91C1C)   // red
        case .unknown:           return Color.fgMuted
        }
    }

    var background: Color { color.opacity(0.14) }

    /// Whether this verdict counts as compliant for the summary.
    var isCompliant: Bool { self == .appStore || self == .verifiedDeveloper }
}

/// One installed app with its derived license/compliance status.
struct AppLicense: Identifiable, Sendable {
    let app: InstalledApp
    var signature: SignatureInfo
    var store: StoreInfo?
    var verdict: LicenseVerdict
    /// One-line explanation of the verdict (shown as the row subtitle).
    var reason: String

    var id: String { app.bundleId }
}
