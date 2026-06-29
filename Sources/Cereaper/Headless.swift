import Foundation

/// Headless runner: drives the Agent from the CLI for testing and demo recording.
/// Prints transcript events to stdout (flushed) and a telemetry summary at the end.
enum Headless {
    private static func log(_ s: String) {
        let line = (s + "\n").data(using: .utf8) ?? Data()
        FileHandle.standardOutput.write(line)
    }

    static func run(prompt: String, label: String, done: DispatchSemaphore) async {
        log("=== Cereaper headless: \(label) ===")
        let agent = Agent()
        let record = await agent.run(task: prompt) { event in
            log(event.text)
        }
        log("--- summary ---")
        log("stopped: \(record.stoppedReason)")
        log("steps: \(record.steps.count)")
        for s in record.steps {
            let tps = s.tokensPerSecond.map { String(format: "%.0f", $0) } ?? "n/a"
            let ttft = s.ttftSeconds.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
            log("  step \(s.step): ttft=\(ttft) tps=\(tps) tools=\(s.toolCalls)")
        }
        if !record.finalAnswer.isEmpty {
            log("final: \(record.finalAnswer)")
        }
        done.signal()
    }

    static func race(done: DispatchSemaphore) async {
        log("=== Cereaper race (gemma-4-31b) ===")
        let results = await Race.run(prompt: QAFlow.heroPrompt) { event in
            log(event.text)
        }
        log("--- race summary ---")
        log(Race.summary(results))
        done.signal()
    }
}
