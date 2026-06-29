import AppKit
import ApplicationServices

/// AppController owns the Cereaper window content: a task input, action buttons,
/// and a live transcript. UI only; all agent behavior lives in the Agent module.
final class AppController: NSObject {
    let view: NSView

    private let taskField: NSTextField
    private let startButton: NSButton
    private let smokeButton: NSButton
    private let qaButton: NSButton
    private let transcriptView: NSTextView
    private let transcriptScroll: NSScrollView

    private let agent = Agent()
    private var isRunning = false

    override init() {
        taskField = NSTextField(labelWithString: "")
        startButton = NSButton(title: "Start", target: nil, action: nil)
        smokeButton = NSButton(title: "Smoke", target: nil, action: nil)
        qaButton = NSButton(title: "QA demo", target: nil, action: nil)
        transcriptView = NSTextView()
        transcriptScroll = NSScrollView()
        view = NSView()
        super.init()
        layout()
        wire()
        reportStatus()
    }

    private func reportStatus() {
        let ax = AXPermission.check() ? "✓ AX trusted" : "✗ AX not trusted (grant in System Settings → Privacy → Accessibility)"
        appendLine(ax)
        if !AXPermission.check() { AXPermission.request() }
    }

    private func layout() {
        view.wantsLayer = true

        taskField.placeholderString = "Describe a desktop task for Cereaper…"
        taskField.translatesAutoresizingMaskIntoConstraints = false
        taskField.bezelStyle = .roundedBezel

        for b in [startButton, smokeButton, qaButton] {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.bezelStyle = .rounded
            b.controlSize = .regular
        }

        transcriptView.isEditable = false
        transcriptView.isRichText = false
        transcriptView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        transcriptView.textContainer?.widthTracksTextView = true

        transcriptScroll.translatesAutoresizingMaskIntoConstraints = false
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.documentView = transcriptView

        view.addSubview(taskField)
        view.addSubview(startButton)
        view.addSubview(smokeButton)
        view.addSubview(qaButton)
        view.addSubview(transcriptScroll)

        NSLayoutConstraint.activate([
            taskField.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            taskField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            taskField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            smokeButton.topAnchor.constraint(equalTo: taskField.bottomAnchor, constant: 12),
            smokeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            qaButton.centerYAnchor.constraint(equalTo: smokeButton.centerYAnchor),
            qaButton.leadingAnchor.constraint(equalTo: smokeButton.trailingAnchor, constant: 8),

            startButton.centerYAnchor.constraint(equalTo: smokeButton.centerYAnchor),
            startButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            transcriptScroll.topAnchor.constraint(equalTo: smokeButton.bottomAnchor, constant: 12),
            transcriptScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            transcriptScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            transcriptScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    private func wire() {
        startButton.target = self
        startButton.action = #selector(startTapped)
        smokeButton.target = self
        smokeButton.action = #selector(smokeTapped)
        qaButton.target = self
        qaButton.action = #selector(qaTapped)
    }

    @objc private func smokeTapped() {
        taskField.stringValue = QAFlow.smokePrompt
    }

    @objc private func qaTapped() {
        taskField.stringValue = QAFlow.heroPrompt
    }

    @objc private func startTapped() {
        guard !isRunning else { return }
        let task = taskField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        isRunning = true
        setButtonsEnabled(false)
        appendLine("▸ task: \(task)")
        Task.detached { [weak self] in
            guard let self else { return }
            _ = await self.agent.run(task: task) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            await MainActor.run { [weak self] in
                self?.isRunning = false
                self?.setButtonsEnabled(true)
                self?.appendLine("▸ done")
            }
        }
    }

    private func setButtonsEnabled(_ on: Bool) {
        startButton.isEnabled = on
        smokeButton.isEnabled = on
        qaButton.isEnabled = on
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
