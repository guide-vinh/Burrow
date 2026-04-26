import SwiftUI

/// One labelled group in the body grid: section label on top, then a
/// single rounded card containing the group's category rows. Per the
/// design directions in CLAUDE_CODE_KICKOFF.md, rows share one card
/// background and the gap between them is the only divider.
struct CategoryGroupSection: View {
    let group: CategoryGroup
    let categories: [CleanCategory]
    @ObservedObject var vm: CleanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionLabel(text: displayName(for: group))
            VStack(spacing: Spacing.xs) {
                ForEach(categories) { category in
                    CategoryRow(
                        category: category,
                        scanResult: vm.scanResults[category.id],
                        isSelected: binding(for: category.id)
                    )
                }
            }
            .cardStyle()
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { vm.selectedCategoryIds.contains(id) },
            set: { isOn in
                if isOn { vm.selectedCategoryIds.insert(id) }
                else    { vm.selectedCategoryIds.remove(id) }
            }
        )
    }

    private func displayName(for group: CategoryGroup) -> String {
        switch group.rawValue {
        case "system":    return "System Junk"
        case "browser":   return "Browsers"
        case "developer": return "Developer Tools"
        default:          return group.rawValue.capitalized
        }
    }
}
