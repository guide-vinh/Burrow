import Foundation

struct CleanCatalog: Codable, Hashable {
    let schemaVersion: Int
    let categories: [CleanCategory]
}
