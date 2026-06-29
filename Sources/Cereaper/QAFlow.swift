import Foundation

/// The QA hero flow: build a tiny app → run it → drive it via AX →
/// screenshot → multimodal-verify the UI against intent → report grounded bugs.
///
/// This is a high-level task preset fed into the Agent. It exists so the demo
/// has a reliable, rehearsed starting prompt and so the Race harness can replay
/// the same prompt across providers.
enum QAFlow {
    /// Prompt the agent runs for the hero demo. The target app is intentionally
    /// simple and AX-friendly: a SwiftUI window with a text field and a button.
    static let heroPrompt = """
    Run a self-QA demo end to end, narrating each step via tool calls:

    1. Write a tiny SwiftUI macOS app at /tmp/cereaper-qa/QAApp.swift with this behavior:
       - A window titled "QA Target" with an NSTextField (placeholder "Type your name"),
         a button titled "Greet", and a label below that shows nothing until clicked.
       - When the button is clicked, the label should show "Hello, <name>!" using the
         field's text. (Intentionally ship it with a bug: show "Hello, !" with an empty
         name when the field is empty, but ALSO forget to read the field — just print
         a hardcoded "Hello, world!" so the greeting is wrong for any typed name.)
    2. Write a minimal build script at /tmp/cereaper-qa/build.sh that compiles QAApp.swift
       into an app bundle at /tmp/cereaper-qa/QAApp.app using swiftc and runs it.
    3. Run the build script with bash to launch QAApp.
    4. Call computer_focus on "QAApp" (or the launched app name), then computer_state to
       read the window's AX tree.
    5. Use computer_set_value to type "Ada" into the text field, then computer_click on
       the Greet button.
    6. Take a screenshot and use image_look to verify what the label actually shows.
    7. Report the bug you observed with the grounded element and the actual vs expected
       label text, then call final_answer with the bug report.
    """

    /// A simpler prompt for a first smoke test of the loop (no app-build).
    static let smokePrompt = """
    Take a screenshot of the main screen, then use image_look to describe in one
    sentence what is visible. Then call final_answer with that sentence.
    """
}
