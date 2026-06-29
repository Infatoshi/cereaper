import Foundation

/// Cerebras Chat Completions adapter (OpenAI-compatible).
/// Endpoint: https://api.cerebras.ai/v1/chat/completions
/// Model:    gemma-4-31b  (hackathon private preview; standard Cerebras API key)
///
/// Reasoning is OFF by default on Gemma 4. Set `reasoningEffort` to low/medium/high
/// to turn thinking on. Keep `none` for the action model in the speed race; use
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
        let usage: Usage?
        let timeInfo: TimeInfo?
    }

    /// Non-streaming completion. Round one uses non-streaming; streaming is a later add.
    func complete(
        messages: [Message],
        reasoningEffort: String = "none",
        temperature: Double = 0.2
    ) async throws -> CompletionResult {
        guard isConfigured else { throw CerebrasError.missingAPIKey }

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map(messageJSON),
            "temperature": temperature,
        ]
        if reasoningEffort != "none" {
            body["reasoning_effort"] = reasoningEffort
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw CerebrasError.httpError(snippet)
        }

        let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        let text = decoded.choices.first?.message.content ?? ""
        return CompletionResult(text: text, usage: decoded.usage, timeInfo: decoded.timeInfo)
    }

    /// Quick connectivity + latency probe. Prints tokens/sec from `time_info`.
    func ping() async throws -> CompletionResult {
        try await complete(
            messages: [.system("You are a ping responder."),
                       .user([.text("Reply with exactly: pong")])],
            reasoningEffort: "none",
            temperature: 0
        )
    }

    private func messageJSON(_ m: Message) -> [String: Any] {
        let content: Any
        if m.content.count == 1, case .text = m.content[0].kind, let t = m.content[0].text {
            // Single text block → send as plain string (most compatible).
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
        return ["role": m.role.rawValue, "content": content]
    }
}

private struct CompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String? }
        let message: Message
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
    case httpError(String)
}
