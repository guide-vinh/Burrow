import Foundation

/// Top-level Codable for `AppLeftovers.json` (schema v2). Custom
/// `init(from:)` filters underscore-prefixed keys out of
/// `vendorOverrides` because the schema embeds documentation strings
/// (`_doc`) as siblings of real vendor entries.
struct AppLeftoversCatalog: Codable, Hashable {

    let schemaVersion: Int
    let lastUpdated: String?
    let userPaths: [LeftoverPattern]
    let systemPaths: [LeftoverPattern]
    let vendorOverrides: [String: VendorOverride]
    let ignoreApps: IgnoreApps
    let homebrewDetection: HomebrewDetection
    let macAppStoreDetection: MacAppStoreDetection

    // MARK: - Nested config blocks

    struct IgnoreApps: Codable, Hashable {
        let patterns: [String]
        let reason: String?
    }

    struct HomebrewDetection: Codable, Hashable {
        let caskroomPrefixes: [String]
        let uninstallCommand: String
        let afterCommand: String
        let warningMessage: String
    }

    struct MacAppStoreDetection: Codable, Hashable {
        let receiptPath: String
        let uiHint: String
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, lastUpdated, userPaths, systemPaths,
             vendorOverrides, ignoreApps, homebrewDetection, macAppStoreDetection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.lastUpdated = try c.decodeIfPresent(String.self, forKey: .lastUpdated)
        self.userPaths = try c.decode([LeftoverPattern].self, forKey: .userPaths)
        self.systemPaths = try c.decode([LeftoverPattern].self, forKey: .systemPaths)
        self.ignoreApps = try c.decode(IgnoreApps.self, forKey: .ignoreApps)
        self.homebrewDetection = try c.decode(HomebrewDetection.self, forKey: .homebrewDetection)
        self.macAppStoreDetection = try c.decode(MacAppStoreDetection.self, forKey: .macAppStoreDetection)

        // vendorOverrides: dynamic-keyed dict that includes a `_doc`
        // string sibling. Skip any underscore-prefixed key, then
        // try to decode each remaining value; tolerate per-entry
        // decode failure to be resilient against stray docs.
        let nested = try c.nestedContainer(keyedBy: DynamicKey.self, forKey: .vendorOverrides)
        var overrides: [String: VendorOverride] = [:]
        for key in nested.allKeys where !key.stringValue.hasPrefix("_") {
            if let vo = try? nested.decode(VendorOverride.self, forKey: key) {
                overrides[key.stringValue] = vo
            }
        }
        self.vendorOverrides = overrides
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try c.encode(userPaths, forKey: .userPaths)
        try c.encode(systemPaths, forKey: .systemPaths)
        try c.encode(ignoreApps, forKey: .ignoreApps)
        try c.encode(homebrewDetection, forKey: .homebrewDetection)
        try c.encode(macAppStoreDetection, forKey: .macAppStoreDetection)

        var nested = c.nestedContainer(keyedBy: DynamicKey.self, forKey: .vendorOverrides)
        for (key, value) in vendorOverrides {
            try nested.encode(value, forKey: DynamicKey(stringValue: key)!)
        }
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
