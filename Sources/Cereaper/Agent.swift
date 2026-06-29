import Foundation

/// The agent loop. Round-one scaffold: ping + single completion.
/// The real loop (tool calls, step budget, final_answer, visual verification)
/// is layered in next, on top of this skeleton.
///
/// Design rules carried over from tau:
/// - fail closed instead of guessing
/// - hard step budget (no runaway loops)
/// - tool-call-only outputs via structured outputs once tools are wired
final class Agent {
    private let client: CerebrasClient

    init(client: CerebrasClient = CerebrasClient()) {
        self.client = client
    }

    func run(task: String, onEvent: @escaping (TranscriptEvent) -> Void) async {
        guard client.isConfigured else {
            onEvent(.init(text: "✗ CEREBRAS_API_KEY not set. Export it and relaunch."))
            return
        }

        onEvent(.init(text: "↯ pinging Cerebras (gemma-4-31b)…"))
        do {
            let ping = try await client.ping()
            let tps = ping.timeInfo?.tokensPerSecond.map { String(format: "%.0f", $0) } ?? "n/a"
            let ttft = ping.timeInfo?.timeToFirstTokenMs.map { String(format: "%.0f ms", $0) } ?? "n/a"
            onEvent(.init(text: "✓ pong — TTFT \(ttft), \(tps) tok/s"))
            onEvent(.init(text: "  reply: \(ping.text)"))
        } catch {
            onEvent(.init(text: "✗ ping failed: \(error)"))
            return
        }

        // Round-one placeholder: a single grounded completion on the task.
        // The tool-calling loop replaces this next.
        do {
            let result = try await client.complete(
                messages: [
                    .system("You are Cereaper, a grounded macOS desktop agent. Be concise."),
                    .user([.text(task)]),
                ],
                reasoningEffort: "none"
            )
            onEvent(.init(text: "▸ plan: \(result.text)"))
        } catch {
            onEvent(.init(text: "✗ completion failed: \(error)"))
        }
    }
}
