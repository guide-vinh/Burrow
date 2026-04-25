import Foundation

enum PathResolver {

    /// Expands a leading `~` to the user's home directory.
    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Resolves a shell-style path that may contain `*` segments. Returns
    /// only URLs that exist on disk. Never throws — unreachable paths
    /// produce an empty array, by design.
    static func resolve(_ path: String) -> [URL] {
        let expanded = expand(path)
        guard !expanded.isEmpty else { return [] }

        let isAbsolute = expanded.hasPrefix("/")
        let segments = expanded
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        let cwd = FileManager.default.currentDirectoryPath
        var current: [URL] = isAbsolute
            ? [URL(fileURLWithPath: "/")]
            : [URL(fileURLWithPath: cwd)]

        for segment in segments {
            if segment.contains("*") {
                current = current.flatMap { url -> [URL] in
                    let contents = (try? FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: []
                    )) ?? []
                    return contents.filter {
                        glob(pattern: segment, matches: $0.lastPathComponent)
                    }
                }
            } else {
                current = current.map { $0.appendingPathComponent(segment) }
            }
        }

        return current.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func glob(pattern: String, matches name: String) -> Bool {
        var regex = "^"
        for char in pattern {
            switch char {
            case "*":
                regex += ".*"
            case ".", "(", ")", "[", "]", "{", "}", "+", "?", "^", "$", "\\", "|":
                regex += "\\\(char)"
            default:
                regex.append(char)
            }
        }
        regex += "$"
        return name.range(of: regex, options: .regularExpression) != nil
    }
}
