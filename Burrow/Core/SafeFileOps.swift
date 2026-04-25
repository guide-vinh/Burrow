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
    static func validate(_ url: URL) throws {
        let path = url.standardizedFileURL.path

        guard FileManager.default.fileExists(atPath: path) else {
            throw SafeFileError.doesNotExist(url)
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

    /// Permanent deletion. Reserved for the "Empty Trash" rule per SPEC
    /// section 6 — every other code path uses `trash(_:)`.
    @discardableResult
    static func permanentlyDelete(_ url: URL, dryRun: Bool = false) throws -> Int64 {
        try validate(url)
        let bytes = size(url)
        if !dryRun {
            try FileManager.default.removeItem(at: url)
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
