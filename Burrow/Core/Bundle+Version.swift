import Foundation

extension Bundle {
    /// `CFBundleShortVersionString` ("0.2.9"); "—" when missing.
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
