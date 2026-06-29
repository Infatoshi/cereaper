import Foundation

/// Per-step timing record accumulated by a run. The Race harness reads these.
struct StepRecord {
    let step: Int
    let ttftSeconds: Double?
    let tokensPerSecond: Double?
    let totalSeconds: Double?
    let promptTokens: Int?
    let completionTokens: Int?
    let reasoningTokens: Int?
    let toolCalls: [String]
}

struct RunRecord {
    var steps: [StepRecord] = []
    var finalAnswer: String = ""
    var stoppedReason: String = ""
}

struct AgentConfig {
    var maxSteps: Int = 24
    var reasoningEffort: String = "none"  // action model: fast
    var verifyReasoningEffort: String = "high"  // (unused; image_look uses none for speed)
    var temperature: Double = 0.2
}

/// The agent loop. Tool-calling, fail-closed, hard step budget, final_answer
/// termination. Image_look verification uses high reasoning; everything else
/// runs at none for speed.
final class Agent {
    let client: CerebrasClient
    let config: AgentConfig
    let registry: ToolRegistry

    init(client: CerebrasClient = CerebrasClient(),
         config: AgentConfig = AgentConfig(),
         registry: ToolRegistry? = nil) {
        self.client = client
        self.config = config
        if let registry {
            self.registry = registry
        } else {
            self.registry = Agent.defaultRegistry(client: client)
        }
    }

    static func defaultRegistry(client: CerebrasClient) -> ToolRegistry {
        let r = ToolRegistry()
        let session = ComputerUseSession()
        r.register(ReadTool())
        r.register(BashTool())
        r.register(WriteTool())
        r.register(ScreenshotTool(session: session))
        r.register(ImageLookTool(client: client))
        r.register(ComputerFocusTool(session: session))
        r.register(ComputerStateTool(session: session))
        r.register(ComputerClickTool(session: session))
        r.register(ComputerSetValueTool(session: session))
        r.register(ComputerTypeTool())
        r.register(ComputerPressKeyTool())
        r.register(FinalAnswerTool())
        return r
    }

    func run(task: String, onEvent: @escaping (TranscriptEvent) -> Void) async -> RunRecord {
        var record = RunRecord()
        guard client.isConfigured else {
            onEvent(.init(text: "✗ CEREBRAS_API_KEY not set. Export it and relaunch."))
            record.stoppedReason = "no-api-key"
            return record
        }

        var messages: [Message] = [
            .system(Self.systemPrompt(tools: registry.specs.map { $0.function.name })),
            .userText(task),
        ]

        for step in 0..<config.maxSteps {
            do {
                let result = try await client.complete(
                    messages: messages,
                    tools: registry.specs,
                    reasoningEffort: config.reasoningEffort,
                    temperature: config.temperature
                )
                let tps = result.tokensPerSecond
                let ttft = result.timeInfo?.ttftSeconds
                let rec = StepRecord(
                    step: step,
                    ttftSeconds: ttft,
                    tokensPerSecond: tps,
                    totalSeconds: result.timeInfo?.totalTime,
                    promptTokens: result.usage?.promptTokens,
                    completionTokens: result.usage?.completionTokens,
                    reasoningTokens: result.usage?.reasoningTokens,
                    toolCalls: result.toolCalls.map { $0.name }
                )
                record.steps.append(rec)

                let tpsStr = tps.map { String(format: "%.0f", $0) } ?? "n/a"
                if !result.text.isEmpty {
                    onEvent(.init(text: "  [\(tpsStr) tok/s] \(result.text)"))
                }
                if result.toolCalls.isEmpty {
                    record.finalAnswer = result.text
                    record.stoppedReason = "model-done"
                    onEvent(.init(text: "▸ final: \(result.text)"))
                    return record
                }

                // Append the assistant turn with tool calls.
                messages.append(.assistant(text: result.text, toolCalls: result.toolCalls))

                // Intercept final_answer: the argument IS the answer.
                if let fa = result.toolCalls.first(where: { $0.name == "final_answer" }) {
                    record.finalAnswer = fa.argumentsJSON
                    record.stoppedReason = "final_answer"
                    onEvent(.init(text: "▸ final_answer: \(fa.argumentsJSON)"))
                    return record
                }

                for call in result.toolCalls {
                    onEvent(.init(text: "  → \(call.name)(\(call.argumentsJSON))"))
                    let output = await registry.run(call)
                    onEvent(.init(text: "  ← \(output.prefix(300))"))
                    messages.append(.tool(result: output, callId: call.id))
                }
            } catch {
                onEvent(.init(text: "✗ step \(step) failed: \(error)"))
                record.stoppedReason = "error: \(error)"
                return record
            }
        }

        record.stoppedReason = "step-budget-exhausted"
        onEvent(.init(text: "✗ step budget exhausted (\(config.maxSteps))"))
        return record
    }

    static func systemPrompt(tools: [String]) -> String {
        """
        You are Cereaper, a grounded macOS desktop agent running on Gemma 4 31B via Cerebras inference.
        You act on real accessibility targets, verify outcomes with screenshots, and fail closed instead of guessing.

        Runtime tools: \(tools.joined(separator: ", ")).

        Operating rules:
        - Call computer_focus before computer_state, computer_click, computer_set_value, or computer_type.
        - Use computer_state to read the frontmost window's AX tree and target elements by index.
        - After an action that changes UI state, take a screenshot and use image_look to verify the effect before continuing.
        - Use read/bash/write to create and run the apps you test.
        - Never guess coordinates. If a target is not in the AX tree, stop and report it.
        - When the task is complete, call final_answer with a concise summary (and any bugs found).
        - Be terse in free text; prefer tool calls.
        """
    }
}
