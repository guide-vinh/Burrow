import Foundation

struct OperationLogEntry: Codable, Hashable {
    enum Action: String, Codable, Hashable {
        case trash
        case permanentDelete
        case exec
    }

    let timestamp: Date
    let action: Action
    let target: String
    let bytes: Int64?
    let dryRun: Bool
}
