import Foundation

/// Cerebras Chat Completions adapter (OpenAI-compatible).
/// Endpoint: https://api.cerebras.ai/v1/chat/completions
/// Model:    gemma-4-31b  (hackathon private preview; standard Cerebras API key)
///
/// Reasoning is OFF by default on Gemma 4. Set `reasoningEffort` to low/medium/high
/// to turn thinking on. Use `none` for the action model in the speed race; use
/// `high` for the visual-verification step where reasoning helps.
///
/// Image input: base64 data URIs only, via image_url content blocks. No hosted URLs.
struct CerebrasClient {
    let apiKey: String
    let baseURL: URL
    let model: String

    init(
        apiKey: String = ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"] ?? "",
        baseURL: URL = URL(string: "https://api.cerebras.ai/v1")!,
        model: String = "gemma-4-31b"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    struct CompletionResult {
        let text: String
        let toolCalls: [ToolCall]
        let usage: Usage?
        let timeInfo: TimeInfo?
        var tokensPerSecond: Double? { timeInfo?.tokensPerSecond(completionTokens: usage?.completionTokens) }
    }

    /// Non-streaming completion with optional tool definitions. Round one uses
    /// non-streaming; streaming is a later add.
    func complete(
        messages: [Message],
        tools: [ToolSpec] = [],
        reasoningEffort: String = "none",
        temperature: Double = 0.2,
        maxTokens: Int = 2048
    ) async throws -> CompletionResult {
        guard isConfigured else { throw CerebrasError.missingAPIKey }

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map(messageJSON),
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        if reasoningEffort != "none" {
            body["reasoning_effort"] = reasoningEffort
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { try! JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? -1
        guard let http, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw CerebrasError.httpError(code, snippet)
        }

        let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        let choice = decoded.choices.first
        let text = choice?.message.content ?? ""
        let calls = (choice?.message.toolCalls ?? []).map { tc in
            ToolCall(id: tc.id, name: tc.function.name, argumentsJSON: tc.function.arguments)
        }
        return CompletionResult(text: text, toolCalls: calls, usage: decoded.usage, timeInfo: decoded.timeInfo)
    }

    /// Quick connectivity + latency probe.
    func ping() async throws -> CompletionResult {
        try await complete(
            messages: [.system("You are a ping responder."),
                       .userText("Reply with exactly: pong")],
            reasoningEffort: "none",
            temperature: 0,
            maxTokens: 8
        )
    }

    private func messageJSON(_ m: Message) -> [String: Any] {
        let content: Any
        if m.content.count == 1, case .text = m.content[0].kind, let t = m.content[0].text {
            content = t
        } else {
            content = m.content.map { block -> [String: Any] in
                switch block.kind {
                case .text:
                    return ["type": "text", "text": block.text ?? ""]
                case .image_url:
                    return ["type": "image_url",
                            "image_url": ["url": block.imageURI ?? ""]]
                }
            }
        }
        var obj: [String: Any] = ["role": m.role.rawValue, "content": content]
        if let calls = m.toolCalls, !calls.isEmpty {
            obj["tool_calls"] = calls.map { c in
                ["id": c.id, "type": "function",
                 "function": ["name": c.name, "arguments": c.argumentsJSON]]
            }
        }
        if let id = m.toolCallId { obj["tool_call_id"] = id }
        return obj
    }
}

private struct CompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String?
            let toolCalls: [RawToolCall]?
            private enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let message: Message
    }
    struct RawToolCall: Codable {
        let id: String
        let function: RawFunction
        struct RawFunction: Codable { let name: String; let arguments: String }
    }
    let choices: [Choice]
    let usage: Usage?
    let timeInfo: TimeInfo?
    private enum CodingKeys: String, CodingKey {
        case choices, usage
        case timeInfo = "time_info"
    }
}

enum CerebrasError: Error {
    case missingAPIKey
    case httpError(Int, String)
}
