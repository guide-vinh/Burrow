import Foundation
import os

private let logger = Logger(subsystem: "fun.burrow", category: "AppStoreLookup")

/// Looks up an app on the Mac App Store via Apple's public iTunes lookup
/// API to confirm the listing and read its price. Best-effort: returns nil
/// on network failure, timeout, or no match. Sends only the bundle ID.
enum AppStoreLookup {

    private struct Response: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let price: Double?
            let formattedPrice: String?
            let sellerName: String?
            let trackViewUrl: String?
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func lookup(bundleId: String) async -> StoreInfo? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "entity", value: "macSoftware"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let result = decoded.results.first else { return nil }

            let isFree = (result.formattedPrice?.caseInsensitiveCompare("Free") == .orderedSame)
                || (result.price == 0)
            return StoreInfo(
                price: result.price.map { Decimal($0) },
                isFree: isFree,
                sellerName: result.sellerName,
                listingURL: result.trackViewUrl.flatMap(URL.init(string:))
            )
        } catch {
            logger.debug("Lookup failed for \(bundleId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
