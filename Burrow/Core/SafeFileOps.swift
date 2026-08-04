import AppKit
import Foundation

enum SafeFileError: Error {
    case protectedPath(URL)
    case doesNotExist(URL)
    case trashFailed(URL, underlying: Error)
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
    /// Carve-out for Phase 2 Uninstall: a `.app` bundle anywhere under
    /// an Applications root (`/Applications`, `~/Applications`) IS
    /// allowed even though the root is in the deny-list — vendors nest
    /// apps in subfolders (`/Applications/Adobe …/Foo.app`). Helper
    /// bundles nested inside another `.app`, and anything DEEPER than
    /// the bundle itself (e.g. files inside it), remain rejected.
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

    /// True if `path` is a `.app` bundle under an Applications root
    /// (any folder depth) — i.e. an installed application bundle the
    /// user can legitimately uninstall. Bundles nested inside another
    /// `.app` (embedded helpers) are NOT allowed.
    private static func isAllowedAppBundleChild(path: String) -> Bool {
        guard path.hasSuffix(".app") else { return false }
        let appRoots = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        guard let root = appRoots.first(where: { path.hasPrefix($0 + "/") }) else {
            return false
        }
        // No intermediate component between the root and this bundle
        // may itself be a bundle.
        let intermediates = path.dropFirst(root.count + 1).split(separator: "/").dropLast()
        return !intermediates.contains { $0.hasSuffix(".app") }
    }

    /// Moves `url` to the user's Trash via `NSWorkspace.recycle`. Returns
    /// the recursive byte count that was reclaimed. In `dryRun` mode,
    /// computes the size without touching the file system.
    @discardableResult
    static func trash(_ url: URL, dryRun: Bool = false) async throws -> Int64 {
        try validate(url)
        let bytes = size(url)
        if !dryRun {
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
        return bytes
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
