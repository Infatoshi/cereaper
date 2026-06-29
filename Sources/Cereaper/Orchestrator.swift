import Foundation

/// Async subagent delegation on a single Cerebras model.
///
/// The Orchestrator runs a plan of phases (sequential). Each phase contains
/// subtasks that run **in parallel** via a `TaskGroup`. Results are yielded in
/// **completion order** — i.e. as each subagent finishes at its own random time
/// — not in spawn order. After every phase, the orchestrator can pass artifacts
/// (e.g. screenshot paths) forward to later phases. When all phases are done, a
/// single synthesis call combines the subagent findings into the final answer.
///
/// Because every call hits the same fast Cerebras `gemma-4-31b`, the delegation
/// overhead is negligible; the only real latency is image upload, and we share
/// screenshot paths across subagents so an image is uploaded only when a
/// subagent actually needs it.

struct Subtask {
    let role: String
    let instruction: String
    /// Allowed tool names; empty = all. Restricting scopes each subagent to its job.
    let tools: [String]
    /// Hard step budget for this subagent. Inspectors should be tight (3–4) so a
    /// looping model can't spin; builders/navigators get more.
    let maxSteps: Int

    init(role: String, instruction: String, tools: [String], maxSteps: Int = 8) {
        self.role = role
        self.instruction = instruction
        self.tools = tools
        self.maxSteps = maxSteps
    }
}

struct Phase {
    let subtasks: [Subtask]
}

struct OrchestrationPlan {
    let goal: String
    let phases: [Phase]
}

struct SubagentResult {
    let role: String
    let instruction: String
    let record: RunRecord
    var ok: Bool { record.stoppedReason == "final_answer" || record.stoppedReason == "model-done" }
}

/// One subagent: an Agent with a role-scoped system prompt + restricted tools +
/// a tight step budget, running a single subtask to a final_answer.
struct Subagent {
    let client: CerebrasClient
    let config: AgentConfig
    let role: String
    let instruction: String
    let allowedTools: [String]
    let maxSteps: Int
    let session: ComputerUseSession

    func run(onEvent: @escaping @Sendable (RunEvent) -> Void) async -> SubagentResult {
        let registry = Agent.registry(allowed: allowedTools, client: client, session: session)
        var cfg = config
        cfg.maxSteps = maxSteps
        let agent = Agent(client: client, config: cfg, registry: registry)
        agent.systemPromptOverride = Self.rolePrompt(role: role, tools: allowedTools)
        let record = await agent.run(task: instruction, onEvent: onEvent)
        return SubagentResult(role: role, instruction: instruction, record: record)
    }

    static func rolePrompt(role: String, tools: [String]) -> String {
        let available = tools + ["final_answer"]
        return """
        You are the \(role) subagent of Cereaper, a multi-agent desktop QA system.
        You run on Gemma 4 31B via Cerebras. You have ONE job; do exactly it, then stop.
        Tools available: \(available.joined(separator: ", ")).
        - Be terse; prefer tool calls over prose.
        - Call each non-final tool at most ONCE unless a result is clearly unusable.
        - Fail closed: if a target isn't exposed, stop and report it.
        - As soon as you have your answer, call final_answer with it. Do NOT repeat tool calls.
        """
    }
}

final class Orchestrator {
    let client: CerebrasClient
    let config: AgentConfig
    private let session = ComputerUseSession()

    init(client: CerebrasClient = CerebrasClient(), config: AgentConfig = AgentConfig()) {
        self.client = client
        self.config = config
    }

    func run(plan: OrchestrationPlan,
             onEvent: @escaping @Sendable (RunEvent) -> Void) async -> RunRecord {
        var record = RunRecord()
        guard client.isConfigured else {
            onEvent(.status("✗ CEREBRAS_API_KEY not set. Export it and relaunch."))
            onEvent(.stopped("no-api-key"))
            return record
        }

        var priorScreenshots: [URL] = []
        var allResults: [SubagentResult] = []

        for (pi, phase) in plan.phases.enumerated() {
            onEvent(.phase(pi))
            // Spawn this phase's subtasks concurrently. The TaskGroup yields
            // results in completion order — whatever finishes first arrives first.
            let phaseResults = await withTaskGroup(of: SubagentResult.self) { [client, config, session] group in
                for st in phase.subtasks {
                    let resolved = st.instruction.replacingOccurrences(
                        of: "{screenshot}",
                        with: priorScreenshots.last?.path ?? "")
                    onEvent(.subagentStart(role: st.role, instruction: resolved))
                    group.addTask {
                        let sub = Subagent(client: client, config: config, role: st.role,
                                           instruction: resolved, allowedTools: st.tools,
                                           maxSteps: st.maxSteps, session: session)
                        return await sub.run(onEvent: onEvent)
                    }
                }
                var collected: [SubagentResult] = []
                for await r in group {
                    onEvent(.subagentResult(role: r.role,
                                            instruction: r.instruction,
                                            finalAnswer: r.record.finalAnswer,
                                            ok: r.ok))
                    collected.append(r)
                }
                return collected
            }

            allResults.append(contentsOf: phaseResults)
            for r in phaseResults {
                record.steps.append(contentsOf: r.record.steps)
                record.screenshotURLs.append(contentsOf: r.record.screenshotURLs)
                priorScreenshots.append(contentsOf: r.record.screenshotURLs)
            }
        }

        // Synthesis: one model call over all subagent findings → final answer.
        let bundle = allResults.enumerated().map { i, r in
            "[\(r.role)] (\(r.ok ? "ok" : r.record.stoppedReason)) \(r.record.finalAnswer.isEmpty ? "(no answer)" : r.record.finalAnswer)"
        }.joined(separator: "\n")
        do {
            let synth = try await client.complete(
                messages: [
                    .system("You are the Cereaper orchestrator. Given the goal and the subagent findings, produce the concise final report. Compare ACTUAL to EXPECTED and explicitly state whether a bug exists."),
                    .userText("""
                    GOAL: \(plan.goal)

                    SUBAGENT FINDINGS:
                    \(bundle)

                    Produce the final report. If a bug was found, state: element, actual, expected.
                    """),
                ],
                reasoningEffort: "none",
                temperature: 0.2
            )
            record.finalAnswer = synth.text
            record.steps.append(StepRecord(
                step: -1, ttftSeconds: synth.timeInfo?.ttftSeconds,
                tokensPerSecond: synth.tokensPerSecond,
                totalSeconds: synth.timeInfo?.totalTime,
                promptTokens: synth.usage?.promptTokens,
                completionTokens: synth.usage?.completionTokens,
                reasoningTokens: synth.usage?.reasoningTokens,
                toolCalls: ["synthesis"]
            ))
        } catch {
            record.finalAnswer = "synthesis failed: \(error)\n\nSubagent findings:\n\(bundle)"
        }
        record.stoppedReason = "orchestrated"
        onEvent(.finalAnswer(record.finalAnswer))
        onEvent(.stopped(record.stoppedReason))
        return record
    }
}
