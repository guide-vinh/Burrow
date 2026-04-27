import SwiftUI

/// Renders a squarified treemap for an array of `DiskEntry` values.
/// Layout is computed once per `entries` change and cached; hit-testing
/// is handled by an overlay layer of transparent per-rect buttons.
struct TreemapCanvas: View {

    let entries: [DiskEntry]
    let onTap: (DiskEntry) -> Void
    let onContextMenu: (DiskEntry, ContextMenuAction) -> Void

    enum ContextMenuAction {
        case revealInFinder
        case moveToTrash
    }

    // MARK: - State

    @State private var layoutRects: [TreemapLayout.Rect] = []
    @State private var canvasSize: CGSize = .zero
    @State private var hoveredID: UUID?

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // MARK: Canvas layer (fill + stroke + labels)
                Canvas { context, size in
                    for rect in layoutRects {
                        guard let entry = entry(for: rect.id) else { continue }

                        let cgRect = CGRect(x: rect.x, y: rect.y,
                                           width: rect.width, height: rect.height)
                        let path = Path(cgRect)

                        // Fill
                        context.fill(path, with: .color(entry.colorSeed))

                        // Stroke — 1 pt white border between siblings
                        context.stroke(path,
                                       with: .color(.white),
                                       lineWidth: 1)

                        // Labels — only when rect is large enough
                        guard rect.width > 60, rect.height > 24 else { continue }

                        let textColor: Color = entry.colorComponents.brightness < 0.7
                            ? .white
                            : .fgPrimary

                        let padding: CGFloat = Spacing.xs

                        // Line 1: name
                        let nameText = Text(entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textColor)

                        // Line 2: humanSize
                        let sizeText = Text(entry.humanSize)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(textColor)

                        let labelRect = cgRect.insetBy(dx: padding, dy: padding)
                        let lineHeight1: CGFloat = 15
                        let lineHeight2: CGFloat = 14

                        let nameRect = CGRect(x: labelRect.minX,
                                             y: labelRect.minY,
                                             width: labelRect.width,
                                             height: lineHeight1)
                        let sizeRect = CGRect(x: labelRect.minX,
                                             y: labelRect.minY + lineHeight1 + 1,
                                             width: labelRect.width,
                                             height: lineHeight2)

                        context.draw(nameText, in: nameRect)

                        // Only draw size label if there is enough vertical room
                        if rect.height > 24 + lineHeight1 + lineHeight2 + padding * 2 {
                            context.draw(sizeText, in: sizeRect)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                // MARK: Hit-test overlay layer (transparent per-rect buttons)
                ForEach(layoutRects, id: \.id) { rect in
                    if let entry = entry(for: rect.id) {
                        Color.clear
                            .frame(width: CGFloat(rect.width),
                                   height: CGFloat(rect.height))
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                hoveredID = hovering ? entry.id : nil
                            }
                            .help("\(entry.url.path)  ·  \(entry.humanSize)")
                            .onTapGesture {
                                onTap(entry)
                            }
                            .contextMenu {
                                Button {
                                    onContextMenu(entry, .revealInFinder)
                                } label: {
                                    Label("Reveal in Finder",
                                          systemImage: "folder")
                                }

                                Button(role: .destructive) {
                                    onContextMenu(entry, .moveToTrash)
                                } label: {
                                    Label("Move to Trash",
                                          systemImage: "trash")
                                        .foregroundStyle(Color.destructive)
                                }
                            }
                            .position(
                                x: CGFloat(rect.x) + CGFloat(rect.width) / 2,
                                y: CGFloat(rect.y) + CGFloat(rect.height) / 2
                            )
                    }
                }
            }
            .onChange(of: geometry.size) { newSize in
                canvasSize = newSize
                recomputeLayout(in: newSize)
            }
            .onChange(of: entries) { _ in
                recomputeLayout(in: canvasSize)
            }
            .onAppear {
                canvasSize = geometry.size
                recomputeLayout(in: geometry.size)
            }
        }
    }

    // MARK: - Helpers

    private func recomputeLayout(in size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let items = entries.map {
            TreemapLayout.Item(id: AnyHashable($0.id),
                               weight: Double(max($0.size, 1)))
        }
        layoutRects = TreemapLayout.layout(items: items, in: bounds)
    }

    private func entry(for id: AnyHashable) -> DiskEntry? {
        guard let uuid = id.base as? UUID else { return nil }
        return entries.first { $0.id == uuid }
    }
}

// MARK: - Preview

struct TreemapCanvas_Previews: PreviewProvider {

    static let fixtures: [DiskEntry] = {
        let now = Date()
        return [
            DiskEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                url: URL(fileURLWithPath: "/Library/Developer/Xcode"),
                parentURL: URL(fileURLWithPath: "/Library/Developer"),
                name: "Xcode",
                size: 15_000_000_000,
                isDirectory: true,
                modifiedAt: now,
                lastAccessedAt: now,
                childCount: 4200
            ),
            DiskEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator"),
                parentURL: URL(fileURLWithPath: "/Library/Developer"),
                name: "CoreSimulator",
                size: 8_500_000_000,
                isDirectory: true,
                modifiedAt: now,
                lastAccessedAt: nil,
                childCount: 310
            ),
            DiskEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                url: URL(fileURLWithPath: "/Library/Developer/Toolchains"),
                parentURL: URL(fileURLWithPath: "/Library/Developer"),
                name: "Toolchains",
                size: 3_200_000_000,
                isDirectory: true,
                modifiedAt: now,
                lastAccessedAt: nil,
                childCount: 18
            ),
            DiskEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                url: URL(fileURLWithPath: "/Library/Developer/DerivedData"),
                parentURL: URL(fileURLWithPath: "/Library/Developer"),
                name: "DerivedData",
                size: 1_100_000_000,
                isDirectory: true,
                modifiedAt: now,
                lastAccessedAt: now,
                childCount: 87
            ),
            DiskEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                url: URL(fileURLWithPath: "/Library/Developer/Xcode/iOS DeviceSupport"),
                parentURL: URL(fileURLWithPath: "/Library/Developer/Xcode"),
                name: "iOS DeviceSupport",
                size: 400_000_000,
                isDirectory: true,
                modifiedAt: now,
                lastAccessedAt: nil,
                childCount: 6
            )
        ]
    }()

    static var previews: some View {
        TreemapCanvas(
            entries: fixtures,
            onTap: { _ in },
            onContextMenu: { _, _ in }
        )
        .frame(width: 600, height: 400)
    }
}
