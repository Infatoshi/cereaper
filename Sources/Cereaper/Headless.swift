import Foundation

/// Headless runner: drives the Agent from the CLI for testing and demo recording.
/// Prints transcript events to stdout and a telemetry summary at the end.
enum Headless {
    static func run(prompt: String, label: String, done: DispatchSemaphore) async {
        print("=== Cereaper headless: \(label) ===")
        let agent = Agent()
        let record = await agent.run(task: prompt) { event in
            print(event.text)
        }
        print("--- summary ---")
        print("stopped: \(record.stoppedReason)")
        print("steps: \(record.steps.count)")
        for s in record.steps {
            let tps = s.tokensPerSecond.map { String(format: "%.0f", $0) } ?? "n/a"
            let ttft = s.ttftSeconds.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
            print("  step \(s.step): ttft=\(ttft) tps=\(tps) tools=\(s.toolCalls)")
        }
        if !record.finalAnswer.isEmpty {
            print("final: \(record.finalAnswer)")
        }
        done.signal()
    }

    static func race(done: DispatchSemaphore) async {
        print("=== Cereaper race (gemma-4-31b) ===")
        let results = await Race.run(prompt: QAFlow.heroPrompt) { event in
            print(event.text)
        }
        print("--- race summary ---")
        print(Race.summary(results))
        done.signal()
    }
}
