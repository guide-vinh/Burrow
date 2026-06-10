import Foundation
import os

private let logger = Logger(subsystem: "fun.burrow", category: "DockerCacheScanner")

/// Talks to the Docker CLI to find and reclaim cache-like storage.
///
/// Read path:  `docker system df --format '{{json .}}'` → reclaimable
///             bytes per resource class.
/// Write path: `docker … prune --force`.
///
/// Docker reclaims are irreversible (no Trash), so the scanner never
/// prunes on its own — `CleanViewModel.pruneSelectedDocker()` calls
/// `prune(_:)` only after the user confirms in the section's dialog.
/// Everything here is best-effort: if Docker isn't installed or the
/// daemon is down, `scan()` returns `[]` and the section shows its
/// empty state.
///
/// This is the only place in Burrow that shells out via `Process`,
/// and it is gated by the host app being non-sandboxed.
actor DockerCacheScanner {

    // MARK: - Locating docker

    /// Common install locations. Burrow may be launched from Finder,
    /// where `PATH` doesn't include /usr/local/bin, so we probe
    /// explicitly rather than rely on the environment.
    private static func dockerExecutable() -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(home)/.docker/bin/docker",
        ]
        let fm = FileManager.default
        return candidates
            .first { fm.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Scan

    /// Asks the Docker daemon for per-class reclaimable space. Always
    /// returns; emits `[]` (with a log line) if docker is missing, the
    /// daemon is down, or every class is empty.
    func scan() async -> [DockerCacheEntry] {
        guard let docker = Self.dockerExecutable() else {
            logger.info("docker binary not found; skipping Docker scan")
            return []
        }

        guard let output = run(docker, ["system", "df", "--format", "{{json .}}"], timeout: 30) else {
            logger.info("docker system df failed (daemon down?); skipping")
            return []
        }

        var entries: [DockerCacheEntry] = []
        let decoder = JSONDecoder()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let row = try? decoder.decode(DFRow.self, from: data),
                  let kind = DockerCacheEntry.Kind(dfType: row.type) else { continue }

            let reclaimable = Self.parseSize(row.reclaimable)
            guard reclaimable > 0 else { continue }

            let total = Int(row.totalCount) ?? 0
            let active = Int(row.active) ?? 0
            entries.append(DockerCacheEntry(
                kind: kind,
                reclaimableBytes: reclaimable,
                count: max(0, total - active)
            ))
        }

        // Stable declaration order: buildCache, images, containers.
        entries.sort { lhs, rhs in
            let order = DockerCacheEntry.Kind.allCases
            return (order.firstIndex(of: lhs.kind) ?? 0)
                <  (order.firstIndex(of: rhs.kind) ?? 0)
        }

        logger.info("Docker scan: \(entries.count, privacy: .public) reclaimable classes")
        return entries
    }

    // MARK: - Prune

    /// Runs `docker … prune` once per kind in declaration order. Returns
    /// the set that pruned cleanly (exit 0). IRREVERSIBLE — callers
    /// must confirm with the user first.
    func prune(_ kinds: [DockerCacheEntry.Kind]) async -> Set<DockerCacheEntry.Kind> {
        guard let docker = Self.dockerExecutable() else { return [] }
        var succeeded: Set<DockerCacheEntry.Kind> = []
        // Pruning a large image set can be slow; allow generous time.
        let pruneTimeout: TimeInterval = 600
        for kind in kinds {
            if run(docker, kind.pruneArguments, timeout: pruneTimeout) != nil {
                succeeded.insert(kind)
                logger.info("Pruned \(kind.rawValue, privacy: .public)")
            } else {
                logger.error("Prune failed for \(kind.rawValue, privacy: .public)")
            }
        }
        return succeeded
    }

    // MARK: - Size parsing

    /// Parses Docker's human size strings (decimal units, e.g.
    /// "1.234GB", "956.2kB", "0B"). May carry a trailing "(NN%)" which
    /// we ignore. Internal so unit tests can exercise it directly.
    static func parseSize(_ raw: String) -> Int64 {
        let token = raw
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? raw

        // Check longer suffixes first; every unit ends in "B".
        let units: [(String, Double)] = [
            ("PB", 1e15), ("TB", 1e12), ("GB", 1e9),
            ("MB", 1e6),  ("kB", 1e3), ("B",  1),
        ]
        for (suffix, factor) in units where token.hasSuffix(suffix) {
            let numberPart = token.dropLast(suffix.count)
            guard let value = Double(numberPart) else { return 0 }
            return Int64(value * factor)
        }
        return 0
    }

    // MARK: - Subprocess

    /// Runs `executable args…`; returns stdout (UTF-8) on exit 0, else
    /// nil. A watchdog terminates the process after `timeout` seconds
    /// so a wedged daemon can't hang the scan.
    private func run(_ executable: URL, _ args: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = args

        // Quiet, predictable environment. DOCKER_CLI_HINTS off so
        // upsell lines don't pollute --format output.
        var env = ProcessInfo.processInfo.environment
        env["DOCKER_CLI_HINTS"] = "false"
        process.environment = env

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()  // discard

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch docker: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let watchdog = DispatchWorkItem { [weak process] in
            // Best-effort; safe even if the process already exited.
            process?.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // readDataToEndOfFile blocks until EOF, which happens when the
        // process closes its stdout (i.e. exits or is terminated).
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - JSON row

    /// One row from `docker system df --format '{{json .}}'`. Every
    /// field arrives as a string regardless of underlying type.
    private struct DFRow: Decodable {
        let type: String
        let reclaimable: String
        let active: String
        let totalCount: String

        enum CodingKeys: String, CodingKey {
            case type        = "Type"
            case reclaimable = "Reclaimable"
            case active      = "Active"
            case totalCount  = "TotalCount"
        }
    }
}
