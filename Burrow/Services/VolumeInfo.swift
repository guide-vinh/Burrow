import Foundation

/// Reads the capacity of the volume backing a given URL. Used by the
/// Analyze tab to size the storage donut (used vs. free vs. total).
enum VolumeInfo {

    /// Total/free bytes and display name for the volume containing `url`.
    /// Uses `volumeAvailableCapacityForImportantUsage` (what macOS reports
    /// as "available" in About This Mac), falling back to the plain
    /// available capacity. Returns nil if the values can't be read.
    static func capacity(of url: URL) -> (total: Int64, free: Int64, name: String)? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity
        else { return nil }

        let free: Int64
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            free = important
        } else {
            free = Int64(values.volumeAvailableCapacity ?? 0)
        }
        return (total: Int64(total), free: free, name: values.volumeName ?? "Macintosh HD")
    }
}
