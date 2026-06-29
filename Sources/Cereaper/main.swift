import AppKit

// Cereaper entry point. GUI by default; headless modes for testing/recording:
//   swift run --smoke         screenshot + image_look + final_answer
//   swift run --qa            full QA hero flow (single agent)
//   swift run --orchestrate   QA flow as async subagent delegation
//   swift run --race          Cerebras telemetry for the QA prompt

let args = CommandLine.arguments
let done = DispatchSemaphore(value: 0)

switch args.dropFirst().first {
case "--smoke":
    Task { await Headless.run(prompt: QAFlow.smokePrompt, label: "smoke", done: done) }
case "--qa":
    Task { await Headless.run(prompt: QAFlow.heroPrompt, label: "qa", done: done) }
case "--orchestrate":
    Task { await Headless.orchestrate(done: done) }
case "--race":
    Task { await Headless.race(done: done) }
default:
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

if args.dropFirst().first?.hasPrefix("--") == true {
    done.wait()
}

