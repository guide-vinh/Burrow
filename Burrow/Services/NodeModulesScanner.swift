import Foundation
import os

private let logger = Logger(subsystem: "fun.burrow", category: "NodeModulesScanner")

/// Walks the user's home directory looking for `node_modules` folders.
/// Read-only — destructive operations go through `SafeFileOps`.
///
/// Skips:
///   - hidden directories (`.git`, `.cache`, …) to avoid traversing
///     repository internals
///   - `~/Library` (system-managed; node_modules don't live there)
///   - the *contents* of any `node_modules` we find (no need to recurse
///     into nested transitive deps — they're counted via `size(url:)`)
actor NodeModulesScanner {

    /// Standard scan: starts from `~/`. Bounded by `maxDepth` so a
    /// pathological symlink loop can't burn forever.
    func scanHomeDirectory(maxDepth: Int = 8) async -> [NodeModulesEntry] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return scan(root: home, maxDepth: maxDepth)
    }

    // MARK: - Private

    private func scan(root: URL, maxDepth: Int) -> [NodeModulesEntry] {
        var found: [NodeModulesEntry] = []
        var stack: [(URL, Int)] = [(root, 0)]
        let fm = FileManager.default
        let libraryPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .standardizedFileURL.path

        while let (dir, depth) = stack.popLast() {
            // Skip ~/Library — never contains user node_modules and is huge.
            if dir.standardizedFileURL.path.hasPrefix(libraryPath) { continue }
            if depth > maxDepth { continue }

            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            } catch {
                continue
            }

            for child in children {
                let resolved: URLResourceValues
                do {
                    resolved = try child.resourceValues(forKeys: [
                        .isDirectoryKey, .isSymbolicLinkKey,
                    ])
                } catch { continue }

                guard resolved.isDirectory == true,
                      resolved.isSymbolicLink != true else { continue }

                if child.lastPathComponent == "node_modules" {
                    if let entry = makeEntry(nodeModules: child, parent: dir) {
                        found.append(entry)
                    }
                    // Don't recurse into node_modules — sub-deps don't
                    // count as separate scan targets.
                    continue
                }

                stack.append((child, depth + 1))
            }
        }

        logger.info("scan complete: \(found.count, privacy: .public) node_modules dirs")
        return found
    }

    private func makeEntry(nodeModules: URL, parent: URL) -> NodeModulesEntry? {
        let fm = FileManager.default
        let nmAttrs = try? fm.attributesOfItem(atPath: nodeModules.path)
        let nmMtime = (nmAttrs?[.modificationDate] as? Date) ?? .distantPast

        // Newest mtime among parent's direct children except node_modules.
        var parentMtime: Date = .distantPast
        if let kids = try? fm.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for kid in kids where kid.lastPathComponent != "node_modules" {
                if let v = try? kid.resourceValues(forKeys: [.contentModificationDateKey]),
                   let m = v.contentModificationDate, m > parentMtime {
                    parentMtime = m
                }
            }
        }
        if parentMtime == .distantPast { parentMtime = nmMtime }

        let bytes = recursiveSize(nodeModules)
        return NodeModulesEntry(
            url: nodeModules,
            parentURL: parent,
            parentName: parent.lastPathComponent.isEmpty ? parent.path : parent.lastPathComponent,
            totalBytes: bytes,
            nodeModulesMtime: nmMtime,
            parentMtime: parentMtime
        )
    }

    /// Recursive byte sum. Uses `FileManager.enumerator` with
    /// `.totalFileAllocatedSizeKey` to match what Finder's "Get Info"
    /// reports. Errors on individual entries are swallowed.
    private func recursiveSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let v = try? fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey, .isRegularFileKey,
            ]), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
