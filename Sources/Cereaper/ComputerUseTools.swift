import Foundation
import ApplicationServices

/// Holds the currently focused app so state/click/set_value tools operate on the
/// same locked target. Mirrors tau's per-turn focus lock (relaxed for round one).
final class ComputerUseSession {
    var currentApp: AXUIElement?
    var currentAppName: String?
}

final class ComputerFocusTool: Tool {
    let name = "computer_focus"
    let spec = ToolSpec(type: "function", function: .init(
        name: "computer_focus",
        description: "Focus (activate) a macOS app by name so subsequent computer_use actions target it. Call this before any other computer_use action.",
        parameters: .object([
            (name: "app", schema: .string(description: "App name, e.g. Safari, Notes, or a generated app's name"), required: true),
        ])
    ))
    let session: ComputerUseSession
    init(session: ComputerUseSession) { self.session = session }
    func run(argumentsJSON: String) async throws -> String {
        let app = try Self.stringArg("app", from: argumentsJSON)
        do {
            let el = try AXGround.focusApp(app)
            session.currentApp = el
            session.currentAppName = app
            return "focused: \(app)"
        } catch {
            session.currentApp = nil
            return "error focusing \(app): \(error)"
        }
    }
}

final class ComputerStateTool: Tool {
    let name = "computer_state"
    let spec = ToolSpec(type: "function", function: .init(
        name: "computer_state",
        description: "Return a JSON tree of the focused app's frontmost window with element indices. Use indices to target click/set_value.",
        parameters: .object([])
    ))
    let session: ComputerUseSession
    init(session: ComputerUseSession) { self.session = session }
    func run(argumentsJSON: String) async throws -> String {
        guard let app = session.currentApp else {
            return "error: no focused app. Call computer_focus first."
        }
        do {
            let tree = try AXGround.frontmostWindowTree(app)
            let data = try JSONEncoder().encode(tree)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "error reading state: \(error)"
        }
    }
}

final class ComputerClickTool: Tool {
    let name = "computer_click"
    let spec = ToolSpec(type: "function", function: .init(
        name: "computer_click",
        description: "Press (click) the AX element at the given index in the focused window.",
        parameters: .object([
            (name: "index", schema: .integer(description: "Element index from computer_state"), required: true),
        ])
    ))
    let session: ComputerUseSession
    init(session: ComputerUseSession) { self.session = session }
    func run(argumentsJSON: String) async throws -> String {
        guard let app = session.currentApp else { return "error: no focused app" }
        let idx = try Self.intArg("index", from: argumentsJSON)
        do {
            try AXGround.press(app, index: idx)
            return "pressed index \(idx)"
        } catch { return "error: \(error)" }
    }
}

final class ComputerSetValueTool: Tool {
    let name = "computer_set_value"
    let spec = ToolSpec(type: "function", function: .init(
        name: "computer_set_value",
        description: "Set the value (e.g. text) of the AX element at the given index.",
        parameters: .object([
            (name: "index", schema: .integer(description: "Element index from computer_state"), required: true),
            (name: "value", schema: .string(description: "Value to set"), required: true),
        ])
    ))
    let session: ComputerUseSession
    init(session: ComputerUseSession) { self.session = session }
    func run(argumentsJSON: String) async throws -> String {
        guard let app = session.currentApp else { return "error: no focused app" }
        let idx = try Self.intArg("index", from: argumentsJSON)
        let value = try Self.stringArg("value", from: argumentsJSON)
        do {
            try AXGround.setValue(app, index: idx, value: value)
            return "set index \(idx) = \(value)"
        } catch { return "error: \(error)" }
    }
}

final class ComputerTypeTool: Tool {
    let name = "computer_type"
    let spec = ToolSpec(type: "function", function: .init(
        name: "computer_type",
        description: "Type text into the currently focused control via simulated key events.",
        parameters: .object([
            (name: "text", schema: .string(description: "Text to type"), required: true),
        ])
    ))
    func run(argumentsJSON: String) async throws -> String {
        let text = try Self.stringArg("text", from: argumentsJSON)
        AXGround.typeText(text)
        return "typed \(text.count) chars"
    }
}

final class ComputerPressKeyTool: Tool {
    let name = "computer_press_key"
    let spec = ToolSpec(type: "function", function: .init(
        name: "computer_press_key",
        description: "Press a named key: return, tab, space, escape, delete, up, down, left, right, or a letter.",
        parameters: .object([
            (name: "key", schema: .string(description: "Key name, e.g. return"), required: true),
        ])
    ))
    func run(argumentsJSON: String) async throws -> String {
        let key = try Self.stringArg("key", from: argumentsJSON)
        do {
            try AXGround.pressKey(key)
            return "pressed \(key)"
        } catch { return "error: \(error)" }
    }
}

extension Tool {
    static func intArg(_ key: String, from json: String) throws -> Int {
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val = obj[key] as? Int else {
            throw ToolError.missingArg(key)
        }
        return val
    }
}
