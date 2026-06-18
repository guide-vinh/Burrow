import Foundation
import os

private let logger = Logger(subsystem: "fun.burrow", category: "DiskUsageScanner")

/// Fast directory sizing via the system `du(1)` tool — far quicker than a
/// Swift file-by-file walk. Heavy, system-managed folders are pruned by
/// basename during the walk so they don't dominate scan time. Each `scan`
/// spawns its own `du` process, so concurrent calls run in parallel.
enum DiskUsageScanner {

    /// Basenames pruned from every walk: high file count, not user-actionable.
    static let excludedNames: [String] = [
        "Containers", "Group Containers", "Daemon Containers",
        "CoreSimulator", "iOS DeviceSupport",
        "CloudStorage", "Mobile Documents", ".Trash",
    ]

    struct FolderScan: Sendable {
        let total: Int64
        let children: [DiskEntry]   // immediate subdirectories, sizes set
    }

    /// Immediate child directories of `home`, plus the total bytes of loose
    /// files sitting directly in `home`. Cheap one-level listing (hidden
    /// folders included so ~/Library is covered).
    static func topLevel(of home: URL) -> (dirs: [URL], looseBytes: Int64) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        ]
        guard let items = try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: keys, options: []
        ) else { return ([], 0) }

        var dirs: [URL] = []
        var loose: Int64 = 0
        for item in items {
            let std = item.standardizedFileURL
            guard let v = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            if excludedNames.contains(std.lastPathComponent) { continue }
            if v.isDirectory == true {
                dirs.append(std)
            } else {
                loose += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return (dirs, loose)
    }

    /// Run `du -d 1 -k` on `url`: the folder's recursive total plus its
    /// immediate subdirectories with sizes. Excluded basenames are pruned.
    static func scan(_ url: URL) async -> FolderScan {
        var args = ["-d", "1", "-k"]
        for name in excludedNames { args.append(contentsOf: ["-I", name]) }
        args.append(url.standardizedFileURL.path)

        guard let output = await runDu(args) else {
            return FolderScan(total: 0, children: [])
        }
        return parse(output, root: url.standardizedFileURL)
    }

    // MARK: - Private

    private static func runDu(_ args: [String]) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                // depth-1 output is small, so reading after exit can't deadlock.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8))
            }
            do {
                try process.run()
            } catch {
                logger.error("du launch failed: \(error.localizedDescription, privacy: .public)")
                cont.resume(returning: nil)
            }
        }
    }

    /// Parse `du -k` output ("<kbytes>\t<path>" per line) into a FolderScan.
    static func parse(_ output: String, root: URL) -> FolderScan {
        let rootPath = root.path
        var total: Int64 = 0
        var children: [DiskEntry] = []

        for line in output.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let kb = Int64(line[..<tab].trimmingCharacters(in: .whitespaces)) ?? 0
            let path = String(line[line.index(after: tab)...])
            let bytes = kb * 1024

            if path == rootPath {
                total = bytes
                continue
            }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if excludedNames.contains(url.lastPathComponent) { continue }
            children.append(DiskEntry(
                id: UUID(),
                url: url,
                parentURL: root,
                name: url.lastPathComponent,
                size: bytes,
                isDirectory: true,
                modifiedAt: Date(),
                lastAccessedAt: nil,
                childCount: 0
            ))
        }
        return FolderScan(total: total, children: children)
    }
}
