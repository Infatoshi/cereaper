import Foundation

/// The QA hero flow: build a tiny app → run it → drive it via AX →
/// screenshot → multimodal-verify the UI against intent → report grounded bugs.
///
/// This is a high-level task preset fed into the Agent. It exists so the demo
/// has a reliable, rehearsed starting prompt and so the Race harness can replay
/// the same prompt across providers.
enum QAFlow {
    /// Prompt the agent runs for the hero demo. The target app is a known-good
    /// AppKit program (compiles cleanly with swiftc, exposes AX reliably) that
    /// ships with an intentional bug: the Greet button ignores the text field
    /// and always shows "Hello, world!".
    static let heroPrompt = #"""
    Run a self-QA demo end to end, narrating each step via tool calls.

    1. Create the directory: bash `mkdir -p /tmp/cereaper-qa`.

    2. Write this EXACT content to /tmp/cereaper-qa/QAApp.swift using the write tool:

    ```swift
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
    ```

    3. Build it with this EXACT command (bash):
       `swiftc -parse-as-library -framework Cocoa /tmp/cereaper-qa/QAApp.swift -o /tmp/cereaper-qa/QAApp`

    4. Launch it (bash): `/tmp/cereaper-qa/QAApp & sleep 1`

    5. Call computer_focus with app "QAApp", then computer_state to read the
       frontmost window's AX tree. Identify the text field (placeholder
       "Type your name"), the "Greet" button, and the label by their indices.

    6. Use computer_set_value to put "Ada" into the text field, then
       computer_click on the "Greet" button.

    7. Take a screenshot and use image_look with the question
       "What exact text does the label at the bottom show?"

    8. Compare the actual label text to the expected "Hello, Ada!". Report the
       grounded bug (which element, actual vs expected), then call final_answer
       with the bug report.
    """#

    /// A simpler prompt for a first smoke test of the loop (no app-build).
    static let smokePrompt = """
    Take a screenshot of the main screen, then use image_look to describe in one
    sentence what is visible. Then call final_answer with that sentence.
    """
}
