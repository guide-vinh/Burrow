import Foundation

/// One cleaning rule from `CleanRules.json`. Three kinds; see SPEC
/// section 5 for the catalog schema.
///
/// `olderThanDays` is interpreted against the file's content
/// modification date (mtime), not access time: macOS does not
/// reliably record atime on common filesystems. Entries whose mtime
/// cannot be read are conservatively skipped — RuleEngine never
/// deletes a file whose age it cannot determine.
enum CleanRule: Hashable, Codable {
    case directoryContents(path: String, olderThanDays: Int?, includeHidden: Bool?, needsPrivilege: Bool?)
    case glob(path: String, olderThanDays: Int?, includeHidden: Bool?, needsPrivilege: Bool?)
    case command(exec: String, args: [String]?, needsPrivilege: Bool?)

    private enum CodingKeys: String, CodingKey {
        case kind, path, olderThanDays, includeHidden, needsPrivilege, exec, args
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "directoryContents":
            self = .directoryContents(
                path: try c.decode(String.self, forKey: .path),
                olderThanDays: try c.decodeIfPresent(Int.self, forKey: .olderThanDays),
                includeHidden: try c.decodeIfPresent(Bool.self, forKey: .includeHidden),
                needsPrivilege: try c.decodeIfPresent(Bool.self, forKey: .needsPrivilege)
            )
        case "glob":
            self = .glob(
                path: try c.decode(String.self, forKey: .path),
                olderThanDays: try c.decodeIfPresent(Int.self, forKey: .olderThanDays),
                includeHidden: try c.decodeIfPresent(Bool.self, forKey: .includeHidden),
                needsPrivilege: try c.decodeIfPresent(Bool.self, forKey: .needsPrivilege)
            )
        case "command":
            self = .command(
                exec: try c.decode(String.self, forKey: .exec),
                args: try c.decodeIfPresent([String].self, forKey: .args),
                needsPrivilege: try c.decodeIfPresent(Bool.self, forKey: .needsPrivilege)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "Unknown rule kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .directoryContents(path, days, hidden, priv):
            try c.encode("directoryContents", forKey: .kind)
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(days,   forKey: .olderThanDays)
            try c.encodeIfPresent(hidden, forKey: .includeHidden)
            try c.encodeIfPresent(priv,   forKey: .needsPrivilege)
        case let .glob(path, days, hidden, priv):
            try c.encode("glob", forKey: .kind)
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(days,   forKey: .olderThanDays)
            try c.encodeIfPresent(hidden, forKey: .includeHidden)
            try c.encodeIfPresent(priv,   forKey: .needsPrivilege)
        case let .command(exec, args, priv):
            try c.encode("command", forKey: .kind)
            try c.encode(exec, forKey: .exec)
            try c.encodeIfPresent(args, forKey: .args)
            try c.encodeIfPresent(priv, forKey: .needsPrivilege)
        }
    }
}
