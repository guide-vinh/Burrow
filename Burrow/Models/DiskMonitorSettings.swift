import Foundation
import SystemConfiguration

/// User-filled configuration for the background disk monitor. Everything is
/// off / empty by default; nothing ships pre-configured. The Slack bot token
/// is deliberately NOT part of this struct — it lives in the Keychain
/// (`Keychain`), never in UserDefaults.
struct DiskMonitorSettings: Codable, Equatable {
    var enabled = false
    /// Alert when free space is at or below this percentage (0...100).
    var thresholdPercent: Double = 10
    var intervalMinutes: Int = 60
    /// Volumes to check, as paths on each volume ("/" = startup disk).
    var paths: [String] = ["/"]
    /// Name shown in reports; empty means the computer's name.
    var machineName = ""

    /// Slack channel ID (C0123ABCD), taken from `slackChannelLink`. Empty
    /// disables Slack. chat.postMessage is called with this.
    var slackChannel = ""
    /// The channel link the user pasted, shown back in the field.
    var slackChannelLink = ""
    /// Slack user (U.../W...) or user-group (S...) IDs tagged on alerts.
    var slackMentions: [String] = []
    /// Post to Slack only when a volume is low or unreadable.
    var alertOnly = true
    /// Attach the largest folders in the home directory to alerts.
    var includeTopFolders = true
    /// Show the fullest disk's usage in the menu bar while monitoring.
    var showInMenuBar = true
    /// Whether percentages on screen show space used or space left. Display
    /// only: the alert threshold is always about free space.
    var percentDisplay: PercentDisplay = .used

    enum PercentDisplay: String, Codable, CaseIterable {
        case used, free

        var label: String { self == .used ? "Used" : "Free" }
    }

    static let thresholdPresets: [Double] = [5, 10, 15, 20, 25]
    static let intervalPresets: [Int] = [15, 30, 60, 180, 360]

    // MARK: - Persistence

    init() {}

    /// Missing keys fall back to their defaults, so settings saved by an
    /// older build (before a field existed) still load instead of resetting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DiskMonitorSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        thresholdPercent = try c.decodeIfPresent(Double.self, forKey: .thresholdPercent) ?? d.thresholdPercent
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        paths = try c.decodeIfPresent([String].self, forKey: .paths) ?? d.paths
        machineName = try c.decodeIfPresent(String.self, forKey: .machineName) ?? d.machineName
        slackChannel = try c.decodeIfPresent(String.self, forKey: .slackChannel) ?? d.slackChannel
        slackChannelLink = try c.decodeIfPresent(String.self, forKey: .slackChannelLink) ?? d.slackChannelLink
        slackMentions = try c.decodeIfPresent([String].self, forKey: .slackMentions) ?? d.slackMentions
        alertOnly = try c.decodeIfPresent(Bool.self, forKey: .alertOnly) ?? d.alertOnly
        includeTopFolders = try c.decodeIfPresent(Bool.self, forKey: .includeTopFolders) ?? d.includeTopFolders
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? d.showInMenuBar
        percentDisplay = (try? c.decodeIfPresent(PercentDisplay.self, forKey: .percentDisplay)) ?? d.percentDisplay
    }

    private static let defaultsKey = "diskMonitorSettings"

    static func load(from defaults: UserDefaults = .standard) -> DiskMonitorSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(DiskMonitorSettings.self, from: data)
        else { return DiskMonitorSettings() }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Validation (mirrors diskmon's config rules)

    enum ValidationError: LocalizedError, Equatable {
        case threshold(String)
        case channel(String)
        case mention(String)
        case token

        var errorDescription: String? {
            switch self {
            case .threshold(let s): return "Threshold \"\(s)\" must be a number from 0 to 100."
            case .channel(let s): return "\"\(s)\" isn't a Slack channel link. In Slack, right-click the channel → Copy → Copy link, then paste it here."
            case .mention(let s): return "\"\(s)\" is not a Slack user (U…/W…) or user-group (S…) ID."
            case .token: return "That isn't a Slack token. Copy the Bot User OAuth Token (xoxb-…) from your Slack app's OAuth & Permissions page."
            }
        }
    }

    /// Parses a threshold typed by the user, with or without a trailing %.
    /// Accepts "7.5" and "7,5", since the picker shows the locale's format.
    static func parseThreshold(_ input: String) throws -> Double {
        var s = input.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("%") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(s), value >= 0, value <= 100 else {
            throw ValidationError.threshold(input)
        }
        return value
    }

    /// Returns the channel ID from a channel link copied from Slack
    /// (https://<team>.slack.com/archives/C0123ABCD, or an app.slack.com
    /// /client/<team>/C0123ABCD URL). Only links are accepted — a pasted
    /// link can't be mistyped the way a bare ID or #name can. Empty input
    /// is allowed (Slack off) and returns "".
    static func parseChannel(_ input: String) throws -> String {
        let link = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.isEmpty { return "" }
        guard let url = URL(string: link),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "slack.com" || host.hasSuffix(".slack.com")
        else { throw ValidationError.channel(link) }

        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        if let i = parts.firstIndex(of: "archives"), i + 1 < parts.count {
            candidate = parts[i + 1]
        } else if let i = parts.firstIndex(of: "client"), i + 2 < parts.count {
            candidate = parts[i + 2]
        } else {
            candidate = nil
        }
        guard let id = candidate, id.range(of: "^[CGD][A-Z0-9]{2,}$", options: .regularExpression) != nil else {
            throw ValidationError.channel(link)
        }
        return id
    }

    /// Applies what the user typed in the channel-link field: the link is
    /// kept for display, its ID for the API. An empty field turns Slack off.
    /// Invalid input throws and changes nothing.
    mutating func applyChannelLink(_ input: String) throws {
        let draft = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = try Self.parseChannel(draft)
        slackChannel = channel
        slackChannelLink = channel.isEmpty ? "" : draft
    }

    /// A pasted Slack token, trimmed; rejects anything not shaped like one
    /// (xoxb-…, xoxp-…), e.g. a half-pasted value or the signing secret.
    static func parseToken(_ input: String) throws -> String {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.range(of: "^xox[a-z]-[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            throw ValidationError.token
        }
        return token
    }

    /// What the token field does with its draft.
    enum TokenCommit: Equatable {
        case none
        case save(String)
        case invalid
    }

    /// Decides what to do with the token draft. Only a finished edit (Return,
    /// focus left, Save, tab closed, app quitting) ever commits: a half-typed
    /// "xoxb-1" already looks valid and must not replace a good token in the
    /// Keychain. A blank draft never touches the stored token.
    static func tokenCommit(draft: String, finished: Bool) -> TokenCommit {
        guard finished, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
        guard let token = try? parseToken(draft) else { return .invalid }
        return .save(token)
    }

    /// Splits a comma-separated list of Slack IDs. Rejects @names, which
    /// Slack would print without notifying anyone. Empty means no tags.
    static func parseMentions(_ input: String) throws -> [String] {
        let ids = input.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for id in ids where id.range(of: "^[UWS][A-Z0-9]{2,}$", options: .regularExpression) == nil {
            throw ValidationError.mention(id)
        }
        return ids
    }

    /// Splits a comma-separated list of volume paths, dropping blanks and
    /// duplicates. Empty input falls back to the startup disk.
    static func parsePaths(_ input: String) -> [String] {
        var seen = Set<String>()
        let paths = input.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return paths.isEmpty ? ["/"] : paths
    }

    /// Name used in reports: the configured one, else the computer's name.
    /// Capped so a pasted essay can't push a Slack section past its limit.
    var displayName: String {
        let trimmed = machineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? Self.computerName : trimmed).prefix(80))
    }

    /// The Mac's name from Sharing settings. Read from the local
    /// configuration store — unlike `Host.current()`, it never does a
    /// network lookup that can block the main thread.
    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ProcessInfo.processInfo.hostName
    }
}
