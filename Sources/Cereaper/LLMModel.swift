import Foundation

/// Canonical message model. Ported in spirit from tau-llm: a small, provider-neutral
/// shape for Chat Completions. Provider oddities stay at the Cerebras adapter boundary.
enum Role: String, Codable {
    case system, user, assistant, tool
}

struct ContentBlock: Codable {
    enum Kind: String, Codable { case text, image_url }
    let kind: Kind
    let text: String?
    /// Base64 data URI only (Cerebras does not accept hosted image URLs yet).
    let imageURI: String?

    static func text(_ s: String) -> ContentBlock {
        ContentBlock(kind: .text, text: s, imageURI: nil)
    }
    static func image(dataURI: String) -> ContentBlock {
        ContentBlock(kind: .image_url, text: nil, imageURI: dataURI)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, text
        case imageURI = "image_uri"
    }
}

struct Message: Codable {
    let role: Role
    let content: [ContentBlock]
    /// Present on assistant messages that requested a tool call.
    var toolCalls: [ToolCall]?
    /// Present on tool-result messages.
    var toolCallId: String?

    static func user(_ blocks: [ContentBlock]) -> Message {
        Message(role: .user, content: blocks, toolCalls: nil, toolCallId: nil)
    }
    static func system(_ s: String) -> Message {
        Message(role: .system, content: [.text(s)], toolCalls: nil, toolCallId: nil)
    }
}

struct ToolCall: Codable {
    let id: String
    let name: String
    let argumentsJSON: String
}

/// Timing telemetry from a Cerebras completion. The race harness lives off this.
struct TimeInfo: Codable {
    let timeToFirstTokenMs: Double?
    let tokensPerSecond: Double?
    let endToEndLatencyMs: Double?
    private enum CodingKeys: String, CodingKey {
        case timeToFirstTokenMs = "time_to_first_token"
        case tokensPerSecond = "tokens_per_second"
        case endToEndLatencyMs = "end_to_end_latency"
    }
}

struct Usage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
