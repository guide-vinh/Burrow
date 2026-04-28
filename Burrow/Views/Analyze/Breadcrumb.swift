import SwiftUI

// MARK: - Breadcrumb

struct Breadcrumb: View {

    let path: [URL]
    let onNavigate: (URL) -> Void

    // MARK: - Ellipsization

    /// Decide which segments to render given a target visible-segment budget.
    /// Returns either the full list (if `path.count <= maxVisible`), or
    /// `[path.first, nil, path[count-2], path[count-1]]` where `nil` is rendered as "…".
    /// Always keeps at least the last 2 segments and the first segment.
    /// For `maxVisible >= path.count`: return `path.map { Optional($0) }` (no ellipsis).
    /// For `maxVisible < 4` and `path.count > maxVisible`: still keep first + ellipsis + last 2 (4 visual slots).
    /// Empty path returns empty array.
    static func ellipsize(path: [URL], maxVisible: Int) -> [URL?] {
        guard !path.isEmpty else { return [] }
        guard path.count > maxVisible else {
            return path.map { Optional($0) }
        }
        // Ellipsize: keep first + nil (ellipsis) + secondToLast + last
        let last = path[path.count - 1]
        let secondToLast = path[path.count - 2]
        let first = path[0]
        return [first, nil, secondToLast, last]
    }

    // MARK: - Display name

    private static func displayName(for url: URL, isFirst: Bool) -> String {
        if isFirst && url.path == "/" {
            return "Macintosh HD"
        }
        let component = url.lastPathComponent
        return component.isEmpty ? "/" : component
    }

    // MARK: - Segments to render

    private var segments: [URL?] {
        if path.count <= 4 {
            return path.map { Optional($0) }
        } else {
            return Breadcrumb.ellipsize(path: path, maxVisible: 4)
        }
    }

    // MARK: - Body

    var body: some View {
        if path.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, urlOrNil in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.fgMuted)
                        }

                        if let url = urlOrNil {
                            let isFirst = (index == 0)
                            let isLast = (index == segments.count - 1)
                            let name = Breadcrumb.displayName(for: url, isFirst: isFirst)

                            if isLast {
                                Button {
                                    onNavigate(url)
                                } label: {
                                    Text(name)
                                        .font(.bodySMed)
                                        .foregroundColor(.fgPrimary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    onNavigate(url)
                                } label: {
                                    Text(name)
                                        .font(.bodyS)
                                        .foregroundColor(.fgSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            // Ellipsis placeholder — non-interactive
                            Text("…")
                                .font(.bodyS)
                                .foregroundColor(.fgMuted)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct Breadcrumb_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1. Empty path
            Breadcrumb(path: [], onNavigate: { _ in })
                .frame(width: 600)
                .padding()

            // 2. 3 segments — no ellipsis
            Breadcrumb(
                path: [
                    URL(fileURLWithPath: "/"),
                    URL(fileURLWithPath: "/Users"),
                    URL(fileURLWithPath: "/Users/vinh")
                ],
                onNavigate: { _ in }
            )
            .frame(width: 600)
            .padding()

            // 3. 8 segments — should ellipsize
            Breadcrumb(
                path: [
                    URL(fileURLWithPath: "/"),
                    URL(fileURLWithPath: "/Users"),
                    URL(fileURLWithPath: "/Users/vinh"),
                    URL(fileURLWithPath: "/Users/vinh/Library"),
                    URL(fileURLWithPath: "/Users/vinh/Library/Application Support"),
                    URL(fileURLWithPath: "/Users/vinh/Library/Application Support/Burrow"),
                    URL(fileURLWithPath: "/Users/vinh/Library/Application Support/Burrow/Logs"),
                    URL(fileURLWithPath: "/Users/vinh/Library/Application Support/Burrow/Logs/2026")
                ],
                onNavigate: { _ in }
            )
            .frame(width: 600)
            .padding()
        }
    }
}
