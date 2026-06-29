import Foundation

/// One line in the UI transcript. Kept as a value type so the Agent module never
/// imports AppKit; the App module is responsible for rendering.
struct TranscriptEvent {
    let text: String
}
