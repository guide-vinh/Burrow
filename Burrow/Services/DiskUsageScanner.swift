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

    /// Every folder up to `depth` levels below `url` with its size, from a
    /// single `du -d <depth> -k` walk (the disk monitor uses depth 2, so it
    /// walks the home folder once instead of once per expanded folder).
    struct TreeScan: Sendable {
        /// Folder path → bytes. A walk stopped early only lists the folders
        /// `du` had finished (it prints each folder after its contents), so
        /// the folder it was inside when stopped is missing entirely.
        let sizes: [String: Int64]
        /// False when the walk was stopped (task cancelled) before the end.
        let complete: Bool
        /// `du` couldn't be started at all.
        var failed = false
    }

    /// Cancelling the task stops `du`; the folders it had finished are still
    /// returned, with `complete == false`. `sameVolume` adds `-x`.
    ///
    /// Output is read as it arrives (a deep listing can exceed the pipe
    /// buffer). Stopping escalates: SIGTERM, then SIGKILL after `killGrace`,
    /// and after another `killGrace` the scan returns what it has even if
    /// `du` hasn't exited — one stuck in uninterruptible I/O (a broken
    /// network or File Provider mount) ignores both signals.
    /// `command` replaces `/usr/bin/du` and its arguments, for tests.
    static func scanTree(
        _ url: URL,
        depth: Int,
        excluding: [String] = [],
        sameVolume: Bool = false,
        killGrace: TimeInterval = 5,
        command: (URL, [String])? = nil
    ) async -> TreeScan {
        var args = ["-d", String(depth), "-k"]
        if sameVolume { args.append("-x") }
        for name in excluding { args.append(contentsOf: ["-I", name]) }
        args.append(url.standardizedFileURL.path)

        let process = Process()
        let run = TreeRun()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<TreeScan, Never>) in
                run.setContinuation(cont)
                process.executableURL = command?.0 ?? URL(fileURLWithPath: "/usr/bin/du")
                process.arguments = command?.1 ?? args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                        run.reachedEOF()
                    } else {
                        run.append(chunk)
                    }
                }
                // terminationHandler, not waitUntilExit(): the latter waits on
                // the calling thread's run loop and can hang on a GCD thread.
                process.terminationHandler = { p in run.exited(normally: p.terminationReason == .exit) }
                if Task.isCancelled {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    run.finish(complete: false)
                    return
                }
                do {
                    try process.run()
                    if Task.isCancelled { stop(process, run, grace: killGrace) }
                } catch {
                    logger.error("du launch failed: \(error.localizedDescription, privacy: .public)")
                    pipe.fileHandleForReading.readabilityHandler = nil
                    run.finish(complete: false, failed: true)
                }
            }
        } onCancel: {
            stop(process, run, grace: killGrace)
        }
    }

    /// SIGTERM now, SIGKILL after `grace`, then give up waiting after
    /// another `grace` and return the output read so far.
    private static func stop(_ process: Process, _ run: TreeRun, grace: TimeInterval) {
        if process.isRunning { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
                run.finish(complete: false)
            }
        }
    }

    /// Collects one `du` run's output and resumes the scan exactly once:
    /// when the output has ended and the process has exited, or when
    /// `finish` is called first (cancelled before launch, launch failed,
    /// or a stuck process that's no longer worth waiting for).
    private final class TreeRun: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var eof = false
        private var exitedNormally: Bool?
        private var resumed = false
        private var continuation: CheckedContinuation<TreeScan, Never>?

        func setContinuation(_ cont: CheckedContinuation<TreeScan, Never>) {
            lock.lock(); continuation = cont; lock.unlock()
        }

        func append(_ chunk: Data) {
            lock.lock(); data.append(chunk); lock.unlock()
        }

        func reachedEOF() {
            lock.lock(); eof = true; lock.unlock()
            finishIfDone()
        }

        func exited(normally: Bool) {
            lock.lock(); exitedNormally = normally; lock.unlock()
            finishIfDone()
        }

        private func finishIfDone() {
            lock.lock()
            let done = eof && exitedNormally != nil
            let complete = exitedNormally == true
            lock.unlock()
            if done { finish(complete: complete) }
        }

        func finish(complete: Bool, failed: Bool = false) {
            lock.lock()
            guard !resumed, let cont = continuation else { lock.unlock(); return }
            resumed = true
            var output = String(decoding: data, as: UTF8.self)
            lock.unlock()
            // A stopped du can end mid-line; drop that fragment so a cut-off
            // path never becomes a bogus folder.
            if !output.hasSuffix("\n") {
                output = output.lastIndex(of: "\n").map { String(output[...$0]) } ?? ""
            }
            cont.resume(returning: TreeScan(sizes: parseSizes(output), complete: complete, failed: failed))
        }
    }

    /// `du -k` lines ("<kbytes>\t<path>") → path → bytes. A line cut short
    /// by termination has no tab or no number and is skipped.
    static func parseSizes(_ output: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for line in output.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let kb = Int64(line[..<tab].trimmingCharacters(in: .whitespaces))
            else { continue }
            let path = URL(fileURLWithPath: String(line[line.index(after: tab)...])).standardizedFileURL.path
            sizes[path] = kb * 1024
        }
        return sizes
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
