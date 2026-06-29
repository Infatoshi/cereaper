import Foundation

/// The QA hero flow expressed as an async subagent delegation plan.
///
/// Phase 1 (builder) → Phase 2 (navigator) → Phase 3 (three parallel inspectors,
/// each finishing at a random time) → synthesis into a combined bug report.
/// This is the demo of true multi-agent coordination on one Cerebras model.
enum QAOrchestration {
    static let appSource = #"""
    import Cocoa

    @main
    struct QAApp {
        static func main() {
            let app = NSApplication.shared
            let delegate = QAAppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
            app.run()
        }
    }

    final class QAAppDelegate: NSObject, NSApplicationDelegate {
        var window: NSWindow?
        var nameField: NSTextField!
        var greetButton: NSButton!
        var label: NSTextField!

        func applicationDidFinishLaunching(_ notification: Notification) {
            let w = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 340, height: 200),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "QA Target"
            nameField = NSTextField(frame: NSRect(x: 20, y: 140, width: 300, height: 24))
            nameField.placeholderString = "Type your name"
            greetButton = NSButton(frame: NSRect(x: 20, y: 100, width: 100, height: 32))
            greetButton.title = "Greet"
            greetButton.target = self
            greetButton.action = #selector(greet)
            label = NSTextField(frame: NSRect(x: 20, y: 60, width: 300, height: 24))
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            label.stringValue = ""
            w.contentView!.addSubview(nameField)
            w.contentView!.addSubview(greetButton)
            w.contentView!.addSubview(label)
            w.makeKeyAndOrderFront(nil)
            self.window = w
            NSApp.activate(ignoringOtherApps: true)
        }

        @objc func greet() {
            label.stringValue = "Hello, world!"
        }
    }
    """#

    static let plan = OrchestrationPlan(
        goal: """
        The QA Target app is a greeting app. It should greet the user by name: after typing \
        "Ada" into the name field and clicking Greet, the label should show "Hello, Ada!". \
        Determine whether the app behaves correctly. If it does not, report the bug with the \
        grounded element, the actual text, and the expected text.
        """,
        phases: [
        // Phase 1: build + run the target app.
        Phase(subtasks: [
            Subtask(role: "builder",
                    instruction: """
                    Build and launch the QA target app, then stop.
                    1. bash: mkdir -p /tmp/cereaper-qa
                    2. write this exact Swift source to /tmp/cereaper-qa/QAApp.swift:
                    ```swift
                    \(appSource)
                    ```
                    3. bash: swiftc -parse-as-library -framework Cocoa /tmp/cereaper-qa/QAApp.swift -o /tmp/cereaper-qa/QAApp
                    4. bash: /tmp/cereaper-qa/QAApp & sleep 1
                    Then call final_answer confirming the app is built and running.
                    """,
                    tools: ["bash", "write", "read"], maxSteps: 8),
        ]),
        // Phase 2: drive the app via AX and capture a screenshot.
        Phase(subtasks: [
            Subtask(role: "navigator",
                    instruction: """
                    Drive the running QA Target app and capture proof.
                    1. computer_focus app "QAApp".
                    2. computer_state to read the frontmost window's AX tree.
                       Identify the text field (placeholder "Type your name"), the "Greet"
                       button, and the label by their indices.
                    3. computer_set_value on the text field to "Ada".
                    4. computer_click on the "Greet" button.
                    5. screenshot to capture the resulting UI.
                    Then call final_answer with a one-line summary and stop.
                    """,
                    tools: ["computer_focus", "computer_state", "computer_set_value",
                            "computer_click", "screenshot"], maxSteps: 8),
        ]),
        // Phase 3: parallel inspectors on the screenshot — finish in random order.
        Phase(subtasks: [
            Subtask(role: "inspector-text",
                    instruction: "Use image_look ONCE on the screenshot at {screenshot} to answer: what exact text does the label at the bottom show? Report just that text, then final_answer.",
                    tools: ["image_look"], maxSteps: 4),
            Subtask(role: "inspector-ocr",
                    instruction: "Use image_look ONCE on the screenshot at {screenshot} to transcribe ALL visible text exactly. Report the transcription, then final_answer.",
                    tools: ["image_look"], maxSteps: 4),
            Subtask(role: "inspector-layout",
                    instruction: "Use image_look ONCE on the screenshot at {screenshot} to describe the UI layout: list every visible control, its role, and its current state. Then final_answer.",
                    tools: ["image_look"], maxSteps: 4),
        ]),
    ])
}
