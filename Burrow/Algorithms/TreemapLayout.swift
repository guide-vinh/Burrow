import CoreGraphics
import Foundation

/// Squarified treemap algorithm. Pure Swift, no UI dependency.
///
/// Reference: Bruls, Huijsen, van Wijk (1999) "Squarified Treemaps"
/// https://www.win.tue.nl/~vanwijk/stm.pdf
///
/// The algorithm packs weighted items into a rectangle so that each
/// item's area is proportional to its weight, while keeping aspect
/// ratios as close to 1:1 as possible (= readable rectangles).
enum TreemapLayout {

    /// One input item: an `id` (so callers can map results back to
    /// their source) and a positive `weight` (typically size in bytes).
    struct Item: Equatable {
        let id: AnyHashable
        let weight: Double

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.weight == rhs.weight
        }
    }

    /// One laid-out rectangle. Coordinates are in the same units
    /// as the input bounds (typically points).
    struct Rect: Equatable {
        let id: AnyHashable
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        static func == (lhs: Rect, rhs: Rect) -> Bool {
            lhs.id == rhs.id
                && lhs.x == rhs.x
                && lhs.y == rhs.y
                && lhs.width == rhs.width
                && lhs.height == rhs.height
        }
    }

    /// Layout `items` within `bounds`. Returns one Rect per item that
    /// has positive weight, all positioned without overlap, all within
    /// bounds. Items with `weight <= 0` are dropped before layout.
    /// Empty input or zero-area bounds returns an empty array.
    /// Layout is deterministic — identical input produces identical
    /// output across calls.
    static func layout(items: [Item], in bounds: CGRect) -> [Rect] {
        // Edge case: zero-area bounds.
        guard bounds.width > 0, bounds.height > 0 else { return [] }

        // Step 1: Filter out non-positive weights, sort descending.
        let filtered = items.filter { $0.weight > 0 }
            .sorted { $0.weight > $1.weight }

        guard !filtered.isEmpty else { return [] }

        // Step 2: Scale weights to areas proportional to total bounds area.
        let totalArea = Double(bounds.width) * Double(bounds.height)
        let totalWeight = filtered.reduce(0.0) { $0 + $1.weight }
        let areaItems: [(id: AnyHashable, area: Double)] = zip(filtered, filtered.map {
            $0.weight * (totalArea / totalWeight)
        }).map { (id: $0.0.id, area: $0.1) }

        // Working rectangle (origin + size in Double).
        var rx = Double(bounds.origin.x)
        var ry = Double(bounds.origin.y)
        var rw = Double(bounds.width)
        var rh = Double(bounds.height)

        var result: [Rect] = []
        result.reserveCapacity(areaItems.count)

        // Step 3-5: Squarified row packing.
        var rowItems: [(id: AnyHashable, area: Double)] = []
        var idx = 0

        while idx < areaItems.count {
            let item = areaItems[idx]

            if rowItems.isEmpty {
                // Always start a new row with the current item.
                rowItems.append(item)
                idx += 1
            } else {
                // Decide: add item to current row or close the row?
                //
                // The "short side" drives the worst-aspect-ratio formula.
                // We always pack along the SHORT axis of the remaining rect:
                //   - wider remaining rect (rw >= rh) → horizontal strip, short side = rh
                //   - taller remaining rect (rh > rw)  → vertical strip,   short side = rw
                let shortSide = min(rw, rh)
                let currentWorst = worstAspectRatio(row: rowItems, shortSide: shortSide)
                let candidateWorst = worstAspectRatio(row: rowItems + [item], shortSide: shortSide)

                if candidateWorst <= currentWorst {
                    // Adding the item improves (or ties) the worst ratio — keep packing.
                    rowItems.append(item)
                    idx += 1
                } else {
                    // Closing the row produces better rectangles — place the row now.
                    let placed = placeRow(rowItems, rx: rx, ry: ry, rw: rw, rh: rh)
                    result.append(contentsOf: placed.rects)
                    // Shrink the working bounds by the row's thickness along the short axis.
                    if rw >= rh {
                        // Horizontal strip consumed `thickness` of height from the top.
                        ry += placed.thickness
                        rh -= placed.thickness
                    } else {
                        // Vertical strip consumed `thickness` of width from the left.
                        rx += placed.thickness
                        rw -= placed.thickness
                    }
                    rowItems = []
                    // Do NOT advance idx — reprocess this item in the updated bounds.
                }
            }
        }

        // Step 5: Place the final (remaining) row.
        if !rowItems.isEmpty {
            let placed = placeRow(rowItems, rx: rx, ry: ry, rw: rw, rh: rh)
            result.append(contentsOf: placed.rects)
        }

        return result
    }
}

// MARK: - Private helpers

/// Compute the worst (largest) aspect ratio for a row of items packed
/// along the short side `w` of the remaining bounds.
///
/// Formula (from Bruls et al. §3):
///   worst(row, w) = max over r_i of:  max(w² · r_i / s²,  s² / (w² · r_i))
///
/// where s = sum of all areas in the row and r_i is each individual area.
/// This is equivalent to max(w²·r_max/s², s²/(w²·r_min)) when evaluated
/// at both extremes, giving the tightest bound in O(1).
private func worstAspectRatio(row: [(id: AnyHashable, area: Double)], shortSide w: Double) -> Double {
    guard w > 0, !row.isEmpty else { return Double.infinity }

    let s = row.reduce(0.0) { $0 + $1.area }
    guard s > 0 else { return Double.infinity }

    // Using the max-area and min-area shortcut keeps this O(1) per call.
    let rMax = row.max(by: { $0.area < $1.area })!.area
    let rMin = row.min(by: { $0.area < $1.area })!.area

    let w2 = w * w
    let s2 = s * s

    // max over all items of max(w²·r_i / s², s² / (w²·r_i))
    // = max(w²·r_max / s², s² / (w²·r_min))
    let candidate1 = w2 * rMax / s2        // worst for largest item
    let candidate2 = s2 / (w2 * rMin)      // worst for smallest item
    return max(candidate1, candidate2)
}

private struct PlacedRow {
    let rects: [TreemapLayout.Rect]
    /// The thickness of this row along the short axis.
    let thickness: Double
}

/// Place a completed row of items into the working bounds.
///
/// Orientation is determined by the aspect ratio of the remaining bounds:
///
/// - `rw >= rh` (wider than tall) → **horizontal strip** across the full
///   width. The strip's thickness is along the height axis:
///     thickness = sum(areas) / rw
///   Items within the strip are laid side by side left→right, each with
///   width proportional to its area: `itemWidth = area / thickness`.
///   The caller advances `ry += thickness; rh -= thickness`.
///
/// - `rh > rw` (taller than wide) → **vertical strip** down the full
///   height. The strip's thickness is along the width axis:
///     thickness = sum(areas) / rh
///   Items within the strip are stacked top→bottom, each with height
///   proportional to its area: `itemHeight = area / thickness`.
///   The caller advances `rx += thickness; rw -= thickness`.
private func placeRow(
    _ row: [(id: AnyHashable, area: Double)],
    rx: Double, ry: Double, rw: Double, rh: Double
) -> PlacedRow {
    let totalRowArea = row.reduce(0.0) { $0 + $1.area }

    if rw >= rh {
        // Horizontal strip: spans full width rw, thickness along height axis.
        // thickness * rw = totalRowArea  →  thickness = totalRowArea / rw
        let thickness = rw > 0 ? totalRowArea / rw : 0
        var currentX = rx
        var rects: [TreemapLayout.Rect] = []
        rects.reserveCapacity(row.count)
        for item in row {
            // itemWidth * thickness = item.area  →  itemWidth = item.area / thickness
            let itemWidth = thickness > 0 ? item.area / thickness : 0
            rects.append(TreemapLayout.Rect(
                id: item.id,
                x: currentX,
                y: ry,
                width: itemWidth,
                height: thickness
            ))
            currentX += itemWidth
        }
        return PlacedRow(rects: rects, thickness: thickness)
    } else {
        // Vertical strip: spans full height rh, thickness along width axis.
        // thickness * rh = totalRowArea  →  thickness = totalRowArea / rh
        let thickness = rh > 0 ? totalRowArea / rh : 0
        var currentY = ry
        var rects: [TreemapLayout.Rect] = []
        rects.reserveCapacity(row.count)
        for item in row {
            // itemHeight * thickness = item.area  →  itemHeight = item.area / thickness
            let itemHeight = thickness > 0 ? item.area / thickness : 0
            rects.append(TreemapLayout.Rect(
                id: item.id,
                x: rx,
                y: currentY,
                width: thickness,
                height: itemHeight
            ))
            currentY += itemHeight
        }
        return PlacedRow(rects: rects, thickness: thickness)
    }
}
