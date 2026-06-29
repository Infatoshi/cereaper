import Foundation

/// Structured events emitted by the agent loop. The GUI renders each case into
/// its own surface (step table, transcript, screenshot preview, final-answer
/// panel, status bar). Headless consumers use `.text` for a plain line.
///
/// Kept AppKit-free so the Agent module never imports UI.
enum RunEvent {
    case text(String)
    case task(String)
    case toolCall(step: Int, name: String, arguments: String)
    case toolResult(step: Int, name: String, result: String)
    case timing(step: Int, ttftSeconds: Double?, tokensPerSecond: Double?, toolCalls: [String])
    case screenshot(URL)
    case finalAnswer(String)
    case stopped(String)
    case status(String)

    /// Single-line rendering for headless / plain-text consumers.
    var text: String {
        switch self {
        case .text(let s): return s
        case .task(let s): return "▸ task: \(s)"
        case .toolCall(_, let n, let a): return "  → \(n)(\(a))"
        case .toolResult(_, let n, let r): return "  ← \(n): \(r)"
        case .timing(let step, let ttft, let tps, _):
            let t = ttft.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
            let p = tps.map { String(format: "%.0f", $0) } ?? "n/a"
            return "  step \(step): ttft=\(t) tps=\(p)"
        case .screenshot(let url): return "  📷 \(url.path)"
        case .finalAnswer(let s): return "▸ final_answer: \(s)"
        case .stopped(let s): return "▸ stopped: \(s)"
        case .status(let s): return s
        }
    }
}
