import Foundation
import os

private let logger = Logger(subsystem: "fun.burrow", category: "FlutterProjectScanner")

/// Walks the user's home directory looking for Flutter/Dart projects —
/// any dir containing `pubspec.yaml`. For each project, records the
/// reclaimable `.dart_tool/` and `build/` caches. Read-only; destructive
/// operations go through `SafeFileOps`.
///
/// Skips:
///   - hidden directories (`.git`, `.dart_tool`, …)
///   - `~/Library` (system-managed)
///   - `node_modules` (the JS-side scanner handles those)
///   - descendants of any project we find (Flutter projects don't nest)
actor FlutterProjectScanner {

    /// Standard scan: starts from `~/`. Bounded by `maxDepth` so a
    /// pathological symlink loop can't burn forever.
    func scanHomeDirectory(maxDepth: Int = 8) async -> [FlutterProjectEntry] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return scan(root: home, maxDepth: maxDepth)
    }

    // MARK: - Private

    private func scan(root: URL, maxDepth: Int) -> [FlutterProjectEntry] {
        var found: [FlutterProjectEntry] = []
        var stack: [(URL, Int)] = [(root, 0)]
        let fm = FileManager.default
        let libraryPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .standardizedFileURL.path

        while let (dir, depth) = stack.popLast() {
            if dir.standardizedFileURL.path.hasPrefix(libraryPath) { continue }
            if depth > maxDepth { continue }

            // pubspec.yaml present → this is a Dart/Flutter project.
            let pubspec = dir.appendingPathComponent("pubspec.yaml")
            if fm.fileExists(atPath: pubspec.path) {
                if let entry = makeEntry(projectDir: dir, pubspec: pubspec) {
                    found.append(entry)
                }
                // Don't recurse — nested Flutter projects are rare and
                // the inner pubspec would just double-count caches.
                continue
            }

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

                // Skip well-known noise dirs so the walk stays fast.
                let name = child.lastPathComponent
                if name == "node_modules" || name == ".dart_tool" { continue }

                stack.append((child, depth + 1))
            }
        }

        logger.info("scan complete: \(found.count, privacy: .public) Flutter/Dart projects")
        return found
    }

    private func makeEntry(projectDir: URL, pubspec: URL) -> FlutterProjectEntry? {
        let fm = FileManager.default
        let pubspecAttrs = try? fm.attributesOfItem(atPath: pubspec.path)
        let pubspecMtime = (pubspecAttrs?[.modificationDate] as? Date) ?? .distantPast

        let dartTool = inspect(projectDir.appendingPathComponent(".dart_tool"))
        let build = inspect(projectDir.appendingPathComponent("build"))

        // Skip projects with no reclaimable caches — nothing to clean.
        if dartTool.url == nil && build.url == nil { return nil }

        return FlutterProjectEntry(
            projectURL: projectDir,
            projectName: projectDir.lastPathComponent.isEmpty
                ? projectDir.path
                : projectDir.lastPathComponent,
            pubspecMtime: pubspecMtime,
            dartToolURL: dartTool.url,
            dartToolBytes: dartTool.bytes,
            dartToolMtime: dartTool.mtime,
            buildURL: build.url,
            buildBytes: build.bytes,
            buildMtime: build.mtime
        )
    }

    /// Returns metadata for `url` if it exists and is a directory, else
    /// `(nil, 0, nil)` so the caller can tell whether the cache exists.
    private func inspect(_ url: URL) -> (url: URL?, bytes: Int64, mtime: Date?) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return (nil, 0, nil)
        }
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let mtime = attrs?[.modificationDate] as? Date
        let bytes = recursiveSize(url)
        return (url, bytes, mtime)
    }

    /// Same accounting as `NodeModulesScanner.recursiveSize` —
    /// `.totalFileAllocatedSizeKey` matches Finder's Get Info.
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
