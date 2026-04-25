import Foundation

struct ScanResult: Hashable {
    let categoryId: String
    let items: [ScanItem]

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }
}
