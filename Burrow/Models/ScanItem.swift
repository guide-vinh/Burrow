import Foundation

struct ScanItem: Hashable, Identifiable {
    let url: URL
    let bytes: Int64

    var id: URL { url }
}
