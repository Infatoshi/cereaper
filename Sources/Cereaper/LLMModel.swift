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
    static func userText(_ s: String) -> Message {
        Message(role: .user, content: [.text(s)], toolCalls: nil, toolCallId: nil)
    }
    static func system(_ s: String) -> Message {
        Message(role: .system, content: [.text(s)], toolCalls: nil, toolCallId: nil)
    }
    static func assistant(text: String, toolCalls: [ToolCall]? = nil) -> Message {
        Message(role: .assistant, content: [.text(text)], toolCalls: toolCalls, toolCallId: nil)
    }
    static func tool(result: String, callId: String) -> Message {
        Message(role: .tool, content: [.text(result)], toolCalls: nil, toolCallId: callId)
    }
}

struct ToolCall: Codable {
    let id: String
    let name: String
    let argumentsJSON: String
}

/// A tool the agent can call, declared in the OpenAI tool-calling schema.
struct ToolSpec: Codable {
    let type: String // always "function"
    let function: FunctionSpec
    struct FunctionSpec: Codable {
        let name: String
        let description: String
        let parameters: JSONSchema
    }
}

/// Minimal JSON-Schema holder. We pass through an opaque object for `parameters`.
/// Non-recursive (no `items`) — our tool schemas use only object/string/integer.
struct JSONSchema: Codable {
    let type: String
    let properties: [String: JSONSchema]?
    let required: [String]?
    let `enum`: [String]?
    let description: String?

    /// Build a simple object schema from property specs.
    static func object(_ props: [(name: String, schema: JSONSchema, required: Bool)],
                       description: String? = nil) -> JSONSchema {
        var propMap: [String: JSONSchema] = [:]
        var reqs: [String] = []
        for p in props {
            propMap[p.name] = p.schema
            if p.required { reqs.append(p.name) }
        }
        return JSONSchema(type: "object", properties: propMap, required: reqs,
                          enum: nil, description: description)
    }
    static func string(description: String? = nil, `enum`: [String]? = nil) -> JSONSchema {
        JSONSchema(type: "string", properties: nil, required: nil,
                   enum: `enum`, description: description)
    }
    static func integer(description: String? = nil) -> JSONSchema {
        JSONSchema(type: "integer", properties: nil, required: nil,
                   enum: nil, description: description)
    }
}

/// Timing telemetry from a Cerebras completion, in SECONDS. The race harness
/// derives tokens/sec and TTFT from these + usage.
struct TimeInfo: Codable {
    let created: Double?
    let queueTime: Double?
    let promptTime: Double?
    let completionTime: Double?
    let totalTime: Double?

    private enum CodingKeys: String, CodingKey {
        case created
        case queueTime = "queue_time"
        case promptTime = "prompt_time"
        case completionTime = "completion_time"
        case totalTime = "total_time"
    }

    /// Approx time-to-first-token = queue + prompt processing (seconds).
    var ttftSeconds: Double? {
        guard let q = queueTime, let p = promptTime else { return nil }
        return q + p
    }
    /// Output tokens per second, derived from usage + completion_time.
    func tokensPerSecond(completionTokens: Int?) -> Double? {
        guard let ct = completionTime, ct > 0, let n = completionTokens, n > 0 else { return nil }
        return Double(n) / ct
    }
}

struct Usage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let imageTokens: Int?
    let reasoningTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case imageTokens = "image_tokens"
    }
    private struct Details: Codable { let reasoningTokens: Int?; let cachedTokens: Int? }
    private struct DetailsWrapper: Codable {
        let completionTokensDetails: Details?
        let promptTokensDetails: Details?
        private enum CodingKeys: String, CodingKey {
            case completionTokensDetails = "completion_tokens_details"
            case promptTokensDetails = "prompt_tokens_details"
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.promptTokens = try c.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        self.completionTokens = try c.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        self.totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        self.imageTokens = try c.decodeIfPresent(Int.self, forKey: .imageTokens)
        let dw = try? decoder.singleValueContainer().decode(DetailsWrapper.self)
        self.reasoningTokens = dw?.completionTokensDetails?.reasoningTokens
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(promptTokens, forKey: .promptTokens)
        try c.encode(completionTokens, forKey: .completionTokens)
        try c.encode(totalTokens, forKey: .totalTokens)
        try c.encodeIfPresent(imageTokens, forKey: .imageTokens)
    }
}
