import Foundation

struct CategoryGroup: Hashable, Codable {
    let rawValue: String

    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    static let system    = CategoryGroup("system")
    static let browser   = CategoryGroup("browser")
    static let developer = CategoryGroup("developer")
}
