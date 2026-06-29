import AppKit

/// AppController owns the Cereaper window content: a task input, a start button,
/// and a live transcript. It is the UI surface only; all agent behavior lives in
/// the Agent module. UI calls into Agent; Agent emits TranscriptEvents back.
final class AppController: NSObject, NSTextViewDelegate {
    let view: NSView

    private let taskField: NSTextField
    private let startButton: NSButton
    private let transcriptView: NSTextView
    private let transcriptScroll: NSScrollView

    private let agent = Agent()
    private var isRunning = false

    override init() {
        taskField = NSTextField(labelWithString: "")
        startButton = NSButton(title: "Start", target: nil, action: nil)
        transcriptView = NSTextView()
        transcriptScroll = NSScrollView()
        view = NSView()
        super.init()
        layout()
        wire()
    }

    private func layout() {
        view.wantsLayer = true

        taskField.placeholderString = "Describe a desktop task for Cereaper…"
        taskField.translatesAutoresizingMaskIntoConstraints = false
        taskField.bezelStyle = .roundedBezel

        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.bezelStyle = .rounded
        startButton.controlSize = .regular

        transcriptView.isEditable = false
        transcriptView.isRichText = false
        transcriptView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        transcriptView.autoresizingMask = [.width]
        transcriptView.textContainer?.widthTracksTextView = true

        transcriptScroll.translatesAutoresizingMaskIntoConstraints = false
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.documentView = transcriptView

        view.addSubview(taskField)
        view.addSubview(startButton)
        view.addSubview(transcriptScroll)

        NSLayoutConstraint.activate([
            taskField.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            taskField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            taskField.trailingAnchor.constraint(equalTo: startButton.leadingAnchor, constant: -12),

            startButton.centerYAnchor.constraint(equalTo: taskField.centerYAnchor),
            startButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            startButton.widthAnchor.constraint(equalToConstant: 90),

            transcriptScroll.topAnchor.constraint(equalTo: taskField.bottomAnchor, constant: 16),
            transcriptScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            transcriptScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            transcriptScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    private func wire() {
        startButton.target = self
        startButton.action = #selector(startTapped)
    }

    @objc private func startTapped() {
        guard !isRunning else { return }
        let task = taskField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        isRunning = true
        startButton.isEnabled = false
        appendLine("▸ task: \(task)")
        Task.detached { [weak self] in
            guard let self else { return }
            await self.agent.run(task: task) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            await MainActor.run { [weak self] in
                self?.isRunning = false
                self?.startButton.isEnabled = true
                self?.appendLine("▸ done")
            }
        }
    }

    private func handle(_ event: TranscriptEvent) {
        appendLine(event.text)
    }

    private func appendLine(_ line: String) {
        let textStorage = transcriptView.textStorage ?? NSTextStorage()
        let mutable = NSMutableAttributedString(string: line + "\n")
        mutable.addAttribute(.font,
                             value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             range: NSRange(location: 0, length: mutable.length))
        textStorage.append(mutable)
        transcriptView.scrollToEndOfDocument(nil)
    }
}
