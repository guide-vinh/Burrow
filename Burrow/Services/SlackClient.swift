import Foundation

/// Posts messages to Slack via `chat.postMessage` with a bot token
/// (xoxb-…) the user supplies. Needs the `chat:write` scope, and the bot
/// must be invited to the channel.
struct SlackClient {
    let token: String
    var session: URLSession = .shared
    var apiURL = URL(string: "https://slack.com/api/chat.postMessage")!

    struct Attachment: Encodable, Equatable {
        let color: String
        let blocks: [Block]
    }

    /// A Block Kit block holding mrkdwn text: a `section` for the body, or
    /// a small grey `context` line (used for the "Sent from Burrow" footer).
    /// Optional fields are left out of the JSON, so one shape covers both.
    struct Block: Encodable, Equatable {
        struct Text: Encodable, Equatable {
            var type = "mrkdwn"
            let text: String
        }

        let type: String
        var text: Text?
        var elements: [Text]?

        static func section(_ mrkdwn: String) -> Block { Block(type: "section", text: Text(text: mrkdwn)) }
        static func context(_ mrkdwn: String) -> Block { Block(type: "context", elements: [Text(text: mrkdwn)]) }

        /// The block's text, whichever field holds it.
        var mrkdwn: String { text?.text ?? elements?.first?.text ?? "" }
    }

    /// `text` is the notification fallback when attachments are set.
    struct Message: Equatable {
        var text: String
        var attachments: [Attachment] = []
    }

    enum SlackError: LocalizedError {
        case http(Int)
        case api(String)

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Slack returned HTTP \(code)."
            case .api(let code): return "Slack error: \(code)."
            }
        }
    }

    /// Renders a user (U…, W…) or user-group (S…) ID as a mention.
    static func mention(_ id: String) -> String {
        id.hasPrefix("S") ? "<!subteam^\(id)>" : "<@\(id)>"
    }

    func post(_ message: Message, to channel: String) async throws {
        struct Body: Encodable {
            let channel: String
            let text: String
            let attachments: [Attachment]?
        }
        struct Reply: Decodable {
            let ok: Bool
            let error: String?
        }

        var request = URLRequest(url: apiURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            channel: channel,
            text: message.text,
            attachments: message.attachments.isEmpty ? nil : message.attachments
        ))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SlackError.http(http.statusCode)
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard reply.ok else { throw SlackError.api(reply.error ?? "unknown") }
    }
}
