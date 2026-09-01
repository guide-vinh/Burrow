import AppKit
import Foundation
import os

/// Opens a pre-filled "New Issue" page on the Burrow GitHub repo so users can
/// report a bug or request a feature without hand-copying environment details.
///
/// GitHub accepts `title`, `body`, and `labels` query params on the
/// `/issues/new` route; we fill the body with a short template plus a
/// diagnostics block (app version, macOS, hardware) that saves a round-trip
/// asking the reporter which build they're on.
enum IssueReporter {
    private static let repo = "guide-vinh/Burrow"
    private static let log = Logger(subsystem: "fun.burrow", category: "IssueReporter")

    /// The kind of report, which pre-selects a GitHub label and body heading.
    enum Kind {
        case bug
        case feature

        var label: String {
            switch self {
            case .bug:     return "bug"
            case .feature: return "enhancement"
            }
        }

        var titlePrefix: String {
            switch self {
            case .bug:     return "[Bug] "
            case .feature: return "[Feature] "
            }
        }

        var bodyTemplate: String {
            switch self {
            case .bug:
                return """
                **What happened?**


                **What did you expect to happen?**


                **Steps to reproduce**
                1.
                2.
                """
            case .feature:
                return """
                **What would you like Burrow to do?**


                **Why is it useful?**

                """
            }
        }
    }

    /// Opens the reporter's browser at a pre-filled new-issue page.
    static func open(_ kind: Kind = .bug) {
        guard let url = newIssueURL(kind) else {
            log.error("Failed to build GitHub issue URL")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Builds the pre-filled `issues/new` URL. Exposed (non-private) so tests
    /// can assert the template and diagnostics without launching a browser.
    static func newIssueURL(_ kind: Kind) -> URL? {
        let body = """
        \(kind.bodyTemplate)

        ---
        _Diagnostics (please keep):_
        \(diagnostics())
        """

        let query = [
            "title": kind.titlePrefix,
            "body": body,
            "labels": kind.label,
        ]
        .map { "\($0.key)=\(percentEncoded($0.value))" }
        .joined(separator: "&")

        return URL(string: "https://github.com/\(repo)/issues/new?\(query)")
    }

    // MARK: - Diagnostics

    /// A markdown bullet list of the info most useful for triage.
    static func diagnostics() -> String {
        """
        - Burrow: \(appVersion) (build \(buildNumber))
        - macOS: \(osVersion)
        - Model: \(hardwareModel)
        """
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// Machine model identifier (e.g. `MacBookPro18,3`) via sysctl — no
    /// subprocess, matching the rest of the app's in-process approach.
    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "—" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    // MARK: - URL encoding

    /// Percent-encodes a query value. We use a restrictive allowed set
    /// (`alphanumerics`) so spaces, newlines, `#`, `&`, `+` — all common in a
    /// markdown body — are encoded rather than breaking the query string.
    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
