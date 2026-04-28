import SwiftUI

/// Right-hand insights sidebar shown alongside the treemap.
/// Displays the five largest entries and oldest-never-opened entries,
/// each row tappable to reveal in Finder.
struct InsightsPanel: View {
    let topLargest: [DiskEntry]
    let oldestNeverOpened: [DiskEntry]
    let onRevealInFinder: (DiskEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // MARK: Top Largest
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionLabel(text: "Top 5 Largest")
                ForEach(Array(topLargest.prefix(5).enumerated()), id: \.offset) { index, entry in
                    LargestEntryRow(
                        rank: index + 1,
                        entry: entry,
                        onReveal: { onRevealInFinder(entry) }
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)

            // MARK: Oldest Never Opened
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionLabel(text: "Oldest Never Opened")
                if oldestNeverOpened.isEmpty {
                    Text("Last-access tracking disabled on this volume.")
                        .font(.bodyS)
                        .foregroundStyle(Color.fgMuted)
                        .padding(.vertical, Spacing.sm)
                } else {
                    ForEach(Array(oldestNeverOpened.prefix(5).enumerated()), id: \.offset) { index, entry in
                        OldestEntryRow(
                            rank: index + 1,
                            entry: entry,
                            onReveal: { onRevealInFinder(entry) }
                        )
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)

            Spacer(minLength: 0)
        }
        .frame(width: 320)
    }
}

// MARK: - LargestEntryRow

private struct LargestEntryRow: View {
    let rank: Int
    let entry: DiskEntry
    let onReveal: () -> Void

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: Spacing.sm) {
                RankCircle(rank: rank)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.bodyS)
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(abbreviatedPath(entry.url))
                        .font(.monoS)
                        .foregroundStyle(Color.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing) {
                    Text(entry.humanSize)
                        .font(.monoM)
                        .foregroundStyle(Color.fgPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - OldestEntryRow

private struct OldestEntryRow: View {
    let rank: Int
    let entry: DiskEntry
    let onReveal: () -> Void

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: Spacing.sm) {
                RankCircle(rank: rank)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.bodyS)
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(relativeAge(entry.lastAccessedAt ?? entry.modifiedAt))
                        .font(.monoS)
                        .foregroundStyle(Color.fgMuted)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RankCircle

private struct RankCircle: View {
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.surfaceTertiary)
                .frame(width: 24, height: 24)
            Text("\(rank)")
                .font(.captionM)
                .foregroundStyle(Color.fgSecondary)
        }
    }
}

// MARK: - Helpers

private func relativeAge(_ date: Date, now: Date = Date()) -> String {
    let days = Int(now.timeIntervalSince(date) / 86_400)
    if days >= 365 {
        return "\(days / 365)y"
    } else if days >= 30 {
        return "\(days / 30)mo"
    } else if days >= 1 {
        return "\(days)d"
    } else {
        return "<1d"
    }
}

private func abbreviatedPath(_ url: URL) -> String {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let parentPath = url.deletingLastPathComponent().path
    if parentPath.hasPrefix(homePath + "/") {
        return "~/" + parentPath.dropFirst(homePath.count + 1)
    } else if parentPath == homePath {
        return "~"
    } else {
        return parentPath
    }
}

// MARK: - Previews

struct InsightsPanel_Previews: PreviewProvider {
    static let now = Date()

    static let topLargest: [DiskEntry] = [
        DiskEntry(
            id: UUID(),
            url: URL(fileURLWithPath: "/Users/user/Library/Application Support/MobileSync/Backup"),
            parentURL: URL(fileURLWithPath: "/Users/user/Library/Application Support/MobileSync"),
            name: "iOS Backups",
            size: 13_312_000_000,
            isDirectory: true,
            modifiedAt: now,
            lastAccessedAt: now,
            childCount: 5
        ),
        DiskEntry(
            id: UUID(),
            url: URL(fileURLWithPath: "/Users/user/Pictures/Photos Library.photoslibrary"),
            parentURL: URL(fileURLWithPath: "/Users/user/Pictures"),
            name: "Photos Library.photoslibrary",
            size: 9_563_000_000,
            isDirectory: true,
            modifiedAt: now,
            lastAccessedAt: now,
            childCount: 1024
        ),
        DiskEntry(
            id: UUID(),
            url: URL(fileURLWithPath: "/Users/user/Movies/Final Cut Pro Library.fcpbundle"),
            parentURL: URL(fileURLWithPath: "/Users/user/Movies"),
            name: "Final Cut Pro Library.fcpbundle",
            size: 6_200_000_000,
            isDirectory: true,
            modifiedAt: now,
            lastAccessedAt: now,
            childCount: 42
        )
    ]

    static let oldestNeverOpened: [DiskEntry] = [
        DiskEntry(
            id: UUID(),
            url: URL(fileURLWithPath: "/Users/user/Documents/old.sketch"),
            parentURL: URL(fileURLWithPath: "/Users/user/Documents"),
            name: "old.sketch",
            size: 48_000_000,
            isDirectory: false,
            modifiedAt: now.addingTimeInterval(-730 * 86_400),
            lastAccessedAt: now.addingTimeInterval(-730 * 86_400),
            childCount: 0
        ),
        DiskEntry(
            id: UUID(),
            url: URL(fileURLWithPath: "/Users/user/Downloads/presentation.key"),
            parentURL: URL(fileURLWithPath: "/Users/user/Downloads"),
            name: "presentation.key",
            size: 22_000_000,
            isDirectory: false,
            modifiedAt: now.addingTimeInterval(-95 * 86_400),
            lastAccessedAt: now.addingTimeInterval(-95 * 86_400),
            childCount: 0
        ),
        DiskEntry(
            id: UUID(),
            url: URL(fileURLWithPath: "/Users/user/Desktop/notes.txt"),
            parentURL: URL(fileURLWithPath: "/Users/user/Desktop"),
            name: "notes.txt",
            size: 4_096,
            isDirectory: false,
            modifiedAt: now.addingTimeInterval(-27 * 86_400),
            lastAccessedAt: now.addingTimeInterval(-27 * 86_400),
            childCount: 0
        )
    ]

    static var previews: some View {
        Group {
            // Preview 1: both sections populated
            InsightsPanel(
                topLargest: topLargest,
                oldestNeverOpened: oldestNeverOpened,
                onRevealInFinder: { _ in }
            )
            .previewDisplayName("Both Sections")

            // Preview 2: atime-disabled — empty oldestNeverOpened
            InsightsPanel(
                topLargest: topLargest,
                oldestNeverOpened: [],
                onRevealInFinder: { _ in }
            )
            .previewDisplayName("Atime Disabled")
        }
        .padding()
        .background(Color.surfaceSecondary)
    }
}
