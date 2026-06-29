import Foundation

/// Cerebras-vs-GPU race harness. Runs the same prompt through Cerebras Gemma 4
/// and a second provider, accumulates per-step telemetry, and prints a comparison
/// the demo video can overlay.
///
/// Round one: Cerebras is the primary; the second provider is optional. If no
/// second provider key is set, we still report Cerebras telemetry so the video
/// has hard numbers (TTFT, tokens/sec, total time).
struct RaceResult {
    let provider: String
    let record: RunRecord
    let wallClockSeconds: Double
}

enum Race {
    /// Run a prompt on Cerebras and (if configured) a GPU provider, return both.
    static func run(prompt: String,
                    cerebras: CerebrasClient = CerebrasClient(),
                    gpuProvider: CerebrasClient? = nil,
                    onEvent: @escaping (RunEvent) -> Void) async -> [RaceResult] {
        var results: [RaceResult] = []

        onEvent(.text("🏁 Cerebras (gemma-4-31b)"))
        let agent = Agent(client: cerebras)
        let t0 = Date()
        let rec = await agent.run(task: prompt, onEvent: onEvent)
        results.append(RaceResult(provider: "Cerebras", record: rec, wallClockSeconds: Date().timeIntervalSince(t0)))

        if let gpu = gpuProvider {
            onEvent(.text("🏁 GPU provider (\(gpu.model))"))
            let agent2 = Agent(client: gpu, registry: Agent.defaultRegistry(client: gpu))
            let t1 = Date()
            let rec2 = await agent2.run(task: prompt, onEvent: onEvent)
            results.append(RaceResult(provider: "GPU-\(gpu.model)", record: rec2,
                                      wallClockSeconds: Date().timeIntervalSince(t1)))
        }
        return results
    }

    /// Render a compact comparison string for the demo overlay / X post.
    static func summary(_ results: [RaceResult]) -> String {
        var lines: [String] = []
        for r in results {
            let steps = r.record.steps.count
            let avgTps: Double = {
                let vals = r.record.steps.compactMap { $0.tokensPerSecond }
                guard !vals.isEmpty else { return 0 }
                return vals.reduce(0, +) / Double(vals.count)
            }()
            let avgTtft: Double = {
                let vals = r.record.steps.compactMap { $0.ttftSeconds }
                guard !vals.isEmpty else { return 0 }
                return vals.reduce(0, +) / Double(vals.count)
            }()
            let toks = r.record.steps.compactMap { $0.completionTokens }.reduce(0, +)
            lines.append(String(format: "%@: steps=%d wall=%.2fs avgTTFT=%.0fms avgTps=%.0f tok/s outTokens=%d",
                                r.provider, steps, r.wallClockSeconds, avgTtft * 1000, avgTps, toks))
        }
        return lines.joined(separator: "\n")
    }
}
