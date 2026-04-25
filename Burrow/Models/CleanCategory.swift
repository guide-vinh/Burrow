import Foundation

struct CleanCategory: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let group: CategoryGroup
    let icon: String
    let risk: RiskLevel
    let defaultEnabled: Bool
    let requiresAppQuit: String?
    let exclude: [String]?
    let rules: [CleanRule]
}
