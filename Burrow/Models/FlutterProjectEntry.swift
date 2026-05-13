import Foundation

/// One discovered Flutter/Dart project (a directory containing
/// `pubspec.yaml`). Produced by `FlutterProjectScanner`. Tracks both
/// `.dart_tool` and `build` caches — either may be absent. Pure data;
/// UI sorts/filters via the published array on the view-model.
struct FlutterProjectEntry: Hashable, Identifiable {
    /// Project directory — parent of `pubspec.yaml`.
    let projectURL: URL

    /// Display name (last path component of `projectURL`).
    let projectName: String

    /// Modification date of `pubspec.yaml` — proxy for last project edit.
    let pubspecMtime: Date

    /// `.dart_tool` directory if it exists, else nil.
    let dartToolURL: URL?
    let dartToolBytes: Int64
    let dartToolMtime: Date?

    /// `build` directory if it exists, else nil.
    let buildURL: URL?
    let buildBytes: Int64
    let buildMtime: Date?

    /// Total reclaimable across both caches.
    var totalBytes: Int64 { dartToolBytes + buildBytes }

    /// Newer of the two cache mtimes — drives the "caches last touched" sort.
    var lastTouchedMtime: Date {
        max(dartToolMtime ?? .distantPast, buildMtime ?? .distantPast)
    }

    /// Caches present in this entry, joined for compact display.
    /// e.g. ".dart_tool + build" or just ".dart_tool".
    var cacheTypesLabel: String {
        var parts: [String] = []
        if dartToolURL != nil { parts.append(".dart_tool") }
        if buildURL != nil { parts.append("build") }
        return parts.joined(separator: " + ")
    }

    var id: URL { projectURL }
}
