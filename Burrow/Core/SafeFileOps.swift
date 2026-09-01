import AppKit
import Foundation

enum SafeFileError: Error {
    case protectedPath(URL)
    case doesNotExist(URL)
    case trashFailed(URL, underlying: Error)
}

/// Carries the human-readable reason a Finder-assisted trash failed (e.g.
/// the user cancelled the admin authentication dialog) so the UI can show
/// it verbatim.
struct FinderTrashError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The single point where Burrow mutates the file system. Every destructive
/// operation passes through `validate(_:)` first.
enum SafeFileOps {

    private static let protectedSystemPaths: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Applications",
        "/Library/Apple",
        "/private/etc",
        "/private/var/db/sudo",
        "/private/var/db/dslocal",
    ]

    private static let protectedHomeRootSuffixes: [String] = [
        "/Documents",
        "/Desktop",
        "/Downloads",
        "/Movies",
        "/Music",
        "/Pictures",
        "/Public",
    ]

    /// Throws if `url` is in the deny-list, equals a protected user-folder
    /// root, or does not exist.
    ///
    /// Carve-out for Phase 2 Uninstall: items under an Applications
    /// root (`/Applications`, `~/Applications`) ARE allowed even though
    /// the root is in the deny-list — vendors nest apps plus companion
    /// files in subfolders (`/Applications/IBM SPSS Statistics/…`), and
    /// uninstall must be able to trash those and the vendor folder
    /// itself. The roots themselves and anything INSIDE a `.app` bundle
    /// (other than the bundle as a whole) remain rejected.
    static func validate(_ url: URL) throws {
        let path = url.standardizedFileURL.path

        guard FileManager.default.fileExists(atPath: path) else {
            throw SafeFileError.doesNotExist(url)
        }

        if isAllowedAppBundleChild(path: path) {
            return
        }

        for protected in protectedSystemPaths {
            if path == protected || path.hasPrefix(protected + "/") {
                throw SafeFileError.protectedPath(url)
            }
        }

        let home = NSHomeDirectory()
        for suffix in protectedHomeRootSuffixes {
            let root = home + suffix
            if path == root {
                throw SafeFileError.protectedPath(url)
            }
        }
    }

    /// True if `path` is an uninstallable item under an Applications
    /// root: a `.app` bundle (any folder depth), a vendor subfolder, or
    /// a loose companion file. Anything inside a `.app` bundle — other
    /// than the bundle as a whole — is NOT allowed.
    private static func isAllowedAppBundleChild(path: String) -> Bool {
        let appRoots = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        guard let root = appRoots.first(where: { path.hasPrefix($0 + "/") }) else {
            return false
        }
        let components = path.dropFirst(root.count + 1).split(separator: "/")
        guard !components.isEmpty else { return false }
        if let bundleIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            return bundleIndex == components.count - 1
        }
        return true
    }

    /// Moves `url` to the user's Trash via `NSWorkspace.recycle`. Returns
    /// the recursive byte count that was reclaimed. In `dryRun` mode,
    /// computes the size without touching the file system.
    @discardableResult
    static func trash(_ url: URL, dryRun: Bool = false) async throws -> Int64 {
        try validate(url)
        let bytes = size(url)
        if !dryRun {
            do {
                try await recycle(url)
            } catch {
                // `recycle` was denied — typically a root-owned app placed by
                // an installer package that the current user can't move to the
                // Trash. Fall back to Finder, which prompts for admin rights
                // and still lands the item in the Trash (reversible). Throws
                // if Finder also fails (e.g. the user cancels the prompt).
                try await MainActor.run { try trashViaFinder(url) }
            }
        }
        return bytes
    }

    /// Moves `url` to the Trash via `NSWorkspace.recycle`. Resumes throwing
    /// on any failure so `trash` can decide whether to fall back to Finder.
    private static func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error {
                    cont.resume(throwing: SafeFileError.trashFailed(url, underlying: error))
                } else {
                    cont.resume()
                }
            }
        }
    }

    /// Asks Finder (via Apple Events) to move `url` to the Trash. Finder
    /// presents the standard admin authentication dialog when elevated
    /// rights are needed, so this succeeds for root-owned installer apps
    /// that `recycle` can't touch — and the item still goes to the Trash,
    /// preserving reversibility. Requires the Automation (Apple Events)
    /// permission plus `NSAppleEventsUsageDescription` in Info.plist.
    @MainActor
    private static func trashViaFinder(_ url: URL) throws {
        // Escape for embedding in an AppleScript string literal.
        let escaped = url.standardizedFileURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Finder\" to delete (POSIX file \"\(escaped)\")"

        guard let script = NSAppleScript(source: source) else {
            throw SafeFileError.trashFailed(
                url,
                underlying: FinderTrashError(message: "Couldn't build the Finder request.")
            )
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Finder couldn't move the item to the Trash."
            throw SafeFileError.trashFailed(url, underlying: FinderTrashError(message: message))
        }

        // The AppleScript can report success while the item survives (e.g. the
        // auth dialog was dismissed). Verify the move actually happened.
        if FileManager.default.fileExists(atPath: url.standardizedFileURL.path) {
            throw SafeFileError.trashFailed(
                url,
                underlying: FinderTrashError(message: "The item is still in place — administrator access may have been denied.")
            )
        }
    }

    /// Permanent deletion, bypassing the Trash. Only reachable from the
    /// "Empty Trash" rule and the explicit, user-confirmed Delete
    /// buttons — every other code path uses `trash(_:)`.
    @discardableResult
    static func permanentlyDelete(_ url: URL, dryRun: Bool = false) async throws -> Int64 {
        try validate(url)
        let bytes = size(url)
        if !dryRun {
            try await Task.detached(priority: .utility) {
                try FileManager.default.removeItem(at: url)
            }.value
        }
        return bytes
    }

    /// Recursive allocated-size measurement, in bytes.
    static func size(_ url: URL) -> Int64 {
        let fm = FileManager.default
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey])

        if values?.isDirectory == true {
            var total: Int64 = 0
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                options: []
            ) else {
                return 0
            }
            for case let fileURL as URL in enumerator {
                let v = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                total += Int64(v?.totalFileAllocatedSize ?? 0)
            }
            return total
        } else {
            return Int64(values?.totalFileAllocatedSize ?? 0)
        }
    }
}
