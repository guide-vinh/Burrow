import Foundation

/// One leftover-detection rule from `AppLeftovers.json`. Substituted
/// at scan time against an `InstalledApp`'s `bundleId` and `name`.
///
/// `matchType` is optional in the JSON — it defaults to `.exact` when
/// omitted, per the schema's `_documentation.matchTypes` note. Several
/// vendorOverride entries (Adobe, Spotify, …) rely on this default.
struct LeftoverPattern: Codable, Hashable {
    let path: String
    let matchType: MatchType
    let risk: Risk
    let category: String
    let needsPrivilege: Bool?
    let description: String

    enum MatchType: String, Codable, Hashable {
        case exact
        case prefix
        case containsBundleId
        case glob
        /// `path` is a base directory (e.g. `~/Library/Application Support`).
        /// The app's name is split into vendor/product word pairs and each
        /// `base/vendor/product` that exists matches — catches data nested
        /// under a vendor folder like `IBM/SPSS Statistics` or `Google/Chrome`.
        case nestedName
    }

    /// User-visible risk class. `safe` is default-checked, `caution`
    /// is default-checked but reviewable, `highValue` is default-
    /// UNCHECKED — the user must explicitly opt in.
    enum Risk: String, Codable, Hashable {
        case safe
        case caution
        case highValue
    }

    /// Convenience memberwise init. The custom `init(from:)` below
    /// suppresses Swift's synthesized memberwise init, so we expose
    /// one manually for tests and Preview blocks.
    init(
        path: String,
        matchType: MatchType = .exact,
        risk: Risk,
        category: String,
        needsPrivilege: Bool? = nil,
        description: String
    ) {
        self.path = path
        self.matchType = matchType
        self.risk = risk
        self.category = category
        self.needsPrivilege = needsPrivilege
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case path, matchType, risk, category, needsPrivilege, description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try c.decode(String.self, forKey: .path)
        self.matchType = try c.decodeIfPresent(MatchType.self, forKey: .matchType) ?? .exact
        self.risk = try c.decode(Risk.self, forKey: .risk)
        self.category = try c.decode(String.self, forKey: .category)
        self.needsPrivilege = try c.decodeIfPresent(Bool.self, forKey: .needsPrivilege)
        self.description = try c.decode(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encode(matchType, forKey: .matchType)
        try c.encode(risk, forKey: .risk)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(needsPrivilege, forKey: .needsPrivilege)
        try c.encode(description, forKey: .description)
    }
}
