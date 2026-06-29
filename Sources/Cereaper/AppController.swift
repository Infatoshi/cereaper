import AppKit
import ApplicationServices

// MARK: - chat model

struct ToolCard {
    var name: String
    var arguments: String
    var result: String?
    var image: NSImage?
}

enum ChatItem {
    case user(String)
    case assistant(text: String, tools: [ToolCard])
}

// MARK: - theme

private enum Theme {
    static let bg          = NSColor(srgbRed: 0.110, green: 0.110, blue: 0.122, alpha: 1)
    static let panel       = NSColor(srgbRed: 0.173, green: 0.173, blue: 0.184, alpha: 1)
    static let bubbleUser  = NSColor(srgbRed: 0.039, green: 0.518, blue: 1.000, alpha: 1)
    static let bubbleAsst  = NSColor(srgbRed: 0.173, green: 0.173, blue: 0.184, alpha: 1)
    static let card        = NSColor(srgbRed: 0.227, green: 0.227, blue: 0.235, alpha: 1)
    static let cardBorder  = NSColor(srgbRed: 0.345, green: 0.345, blue: 0.353, alpha: 1)
    static let text        = NSColor.white
    static let textSub     = NSColor(srgbRed: 0.682, green: 0.682, blue: 0.710, alpha: 1)
    static let textDim     = NSColor(srgbRed: 0.557, green: 0.557, blue: 0.580, alpha: 1)
    static let accent      = NSColor(srgbRed: 0.039, green: 0.518, blue: 1.000, alpha: 1)
    static let mono = { NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) }
    static let textFont = { NSFont.systemFont(ofSize: 13, weight: .regular) }
}

// MARK: - controller

/// Chat UI: a conversation with user + assistant messages, tool calls rendered
/// inline as cards (the tau-harness tools), a compose bar, and a dark theme.
/// All agent behavior lives in the Agent module; this is UI only.
final class AppController: NSObject, NSTextViewDelegate {

    // exposed for AppDelegate + sibling views
    let view: NSView
    private(set) var stepRows: [StepRow] = []
    private(set) var screenshotURLs: [URL] = []
    private(set) var lastRecord: RunRecord?

    private let messageStack: NSStackView
    private let messageScroll: NSScrollView
    private let composeField: NSTextView
    private let composeScroll: NSScrollView
    private let sendButton: NSButton
    private let smokeButton: NSButton
    private let qaButton: NSButton
    private let clearButton: NSButton
    private let statusLeft: NSTextField
    private let statusCenter: NSTextField
    private let statusRight: NSTextField
    private let axDot: NSView
    private let apiDot: NSView

    private let agent = Agent()
    private var items: [ChatItem] = []
    private var currentAssistant: Int? = nil
    private var isRunning = false
    private var isOrchestrating = false
    private var runStart: Date?
    private var clockTimer: Timer?

    private let bubbleMaxWidth: CGFloat = 560

    override init() {
        messageStack = NSStackView()
        messageScroll = NSScrollView()
        composeField = NSTextView()
        composeScroll = NSScrollView()
        sendButton = NSButton(title: "Send", target: nil, action: nil)
        smokeButton = NSButton(title: "Smoke", target: nil, action: nil)
        qaButton = NSButton(title: "QA demo", target: nil, action: nil)
        clearButton = NSButton(title: "New chat", target: nil, action: nil)
        statusLeft = NSTextField(labelWithString: "")
        statusCenter = NSTextField(labelWithString: "")
        statusRight = NSTextField(labelWithString: "")
        axDot = NSView()
        apiDot = NSView()
        view = NSView()
        super.init()
        build()
        wire()
        refreshStatus()
        if !AXPermission.check() { AXPermission.request() }
    }

    // MARK: - build

    private func build() {
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.bg.cgColor

        let header = headerBar()
        let compose = composeBar()
        let status = statusBar()

        messageStack.orientation = .vertical
        messageStack.alignment = .leading
        messageStack.spacing = 14
        messageStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.widthAnchor.constraint(equalToConstant: 0).isActive = false

        messageScroll.documentView = messageStack
        messageScroll.hasVerticalScroller = true
        messageScroll.drawsBackground = false
        messageScroll.translatesAutoresizingMaskIntoConstraints = false
        messageScroll.borderType = .noBorder
        messageScroll.scrollerStyle = .overlay

        view.addSubview(header)
        view.addSubview(messageScroll)
        view.addSubview(compose)
        view.addSubview(status)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            messageScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            messageScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageScroll.bottomAnchor.constraint(equalTo: compose.topAnchor),

            compose.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            compose.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            compose.bottomAnchor.constraint(equalTo: status.topAnchor),

            status.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 26),
        ])

        // Width-tracker so the stack hugs the scroll width (lets bubbles right-align).
        let widthTracker = NSView()
        widthTracker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(widthTracker)
        NSLayoutConstraint.activate([
            widthTracker.topAnchor.constraint(equalTo: messageScroll.topAnchor),
            widthTracker.leadingAnchor.constraint(equalTo: messageScroll.leadingAnchor, constant: 18),
            widthTracker.trailingAnchor.constraint(equalTo: messageScroll.trailingAnchor, constant: -18),
            widthTracker.heightAnchor.constraint(equalToConstant: 0),
        ])
        messageStack.widthAnchor.constraint(equalTo: widthTracker.widthAnchor).isActive = true
    }

    private func headerBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.bg.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Cereaper")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white

        let model = NSTextField(labelWithString: "gemma-4-31b · Cerebras")
        model.translatesAutoresizingMaskIntoConstraints = false
        model.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        model.textColor = Theme.textDim

        for b in [smokeButton, qaButton, clearButton] {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.bezelStyle = .roundRect
            b.controlSize = .small
            b.contentTintColor = Theme.textSub
        }
        sendButton.title = "Send"
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.bezelStyle = .regularSquare
        sendButton.controlSize = .small
        sendButton.keyEquivalent = "\r"

        bar.addSubview(title)
        bar.addSubview(model)
        bar.addSubview(smokeButton)
        bar.addSubview(qaButton)
        bar.addSubview(clearButton)

        NSLayoutConstraint.activate([
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18),

            model.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            model.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),

            clearButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),

            qaButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            qaButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),

            smokeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            smokeButton.trailingAnchor.constraint(equalTo: qaButton.leadingAnchor, constant: -8),
        ])
        return bar
    }

    private func composeBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.bg.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false

        composeField.delegate = self
        composeField.font = Theme.textFont()
        composeField.isRichText = false
        composeField.drawsBackground = true
        composeField.backgroundColor = Theme.panel
        composeField.textColor = .white
        composeField.insertionPointColor = .white
        composeField.textContainerInset = NSSize(width: 8, height: 6)
        composeField.autoresizingMask = [.width]
        composeField.textContainer?.widthTracksTextView = true
        composeField.isVerticallyResizable = true
        composeField.isHorizontallyResizable = false

        composeScroll.documentView = composeField
        composeScroll.translatesAutoresizingMaskIntoConstraints = false
        composeScroll.hasVerticalScroller = true
        composeScroll.drawsBackground = false
        composeScroll.wantsLayer = true
        composeScroll.layer?.cornerRadius = 8
        composeScroll.layer?.backgroundColor = Theme.panel.cgColor

        sendButton.title = "Send"
        sendButton.bezelStyle = .regularSquare
        sendButton.controlSize = .regular
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.contentTintColor = .white

        bar.addSubview(composeScroll)
        bar.addSubview(sendButton)

        NSLayoutConstraint.activate([
            composeScroll.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            composeScroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            composeScroll.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            composeScroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -10),
            composeScroll.heightAnchor.constraint(equalToConstant: 56),

            sendButton.centerYAnchor.constraint(equalTo: composeScroll.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            sendButton.widthAnchor.constraint(equalToConstant: 80),
        ])
        return bar
    }

    private func statusBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.panel.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false

        for l in [statusLeft, statusCenter, statusRight] {
            l.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            l.textColor = Theme.textDim
            l.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(l)
        }
        statusLeft.alignment = .left
        statusCenter.alignment = .center
        statusRight.alignment = .right

        for d in [axDot, apiDot] {
            d.translatesAutoresizingMaskIntoConstraints = false
            d.wantsLayer = true
            d.layer?.cornerRadius = 4
            d.widthAnchor.constraint(equalToConstant: 7).isActive = true
            d.heightAnchor.constraint(equalToConstant: 7).isActive = true
            bar.addSubview(d)
        }

        NSLayoutConstraint.activate([
            axDot.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            axDot.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            statusLeft.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusLeft.leadingAnchor.constraint(equalTo: axDot.trailingAnchor, constant: 6),

            apiDot.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            apiDot.leadingAnchor.constraint(equalTo: statusLeft.trailingAnchor, constant: 14),
            statusRight.leadingAnchor.constraint(equalTo: apiDot.trailingAnchor, constant: 6),
            statusRight.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            statusCenter.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusCenter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),

            statusRight.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
        ])
        return bar
    }

    // MARK: - wiring

    private func wire() {
        sendButton.target = self
        sendButton.action = #selector(runTapped)
        smokeButton.target = self
        smokeButton.action = #selector(smokeTapped)
        qaButton.target = self
        qaButton.action = #selector(qaTapped)
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Cmd+Enter sends
        if commandSelector == #selector(NSTextView.insertNewline(_:)),
           NSEvent.modifierFlags.contains(.command) {
            runTapped()
            return true
        }
        return false
    }

    @objc func smokeTapped() { sendImmediately(QAFlow.smokePrompt) }
    @objc func qaTapped() { orchestrate() }

    @objc func stopTapped() {
        isRunning = false
        setRunUI(running: false)
        appendAssistantText("▸ stop requested (current step will finish)")
    }

    @objc func runTapped() {
        let text = composeField.string
        guard !text.isEmpty else { return }
        composeField.string = ""
        send(text)
    }

    @objc func clearTapped() {
        guard !isRunning else { return }
        agent.resetConversation()
        items.removeAll()
        stepRows.removeAll()
        screenshotURLs.removeAll()
        lastRecord = nil
        currentAssistant = nil
        render()
        refreshStatus()
    }

    @objc func permissionsTapped() {
        AXPermission.request()
        refreshStatus()
    }

    // MARK: - send

    private func sendImmediately(_ text: String) {
        guard !isRunning else { return }
        send(text)
    }

    /// Run the QA flow as async subagent delegation (orchestrator + parallel
    /// inspectors). The chat shows phases + subagent results in completion order.
    private func orchestrate() {
        guard !isRunning else { return }
        isRunning = true
        isOrchestrating = true
        setRunUI(running: true)
        resetLog()
        items.append(.user("QA demo — async subagent delegation"))
        items.append(.assistant(text: "", tools: []))
        currentAssistant = items.count - 1
        render()
        runStart = Date()
        startClock()

        Task.detached { [weak self] in
            guard let self else { return }
            let orchestrator = Orchestrator()
            let record = await orchestrator.run(plan: QAOrchestration.plan) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            await MainActor.run { [weak self] in
                self?.lastRecord = record
                self?.isRunning = false
                self?.isOrchestrating = false
                self?.currentAssistant = nil
                self?.setRunUI(running: false)
                self?.stopClock()
            }
        }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !isRunning else { return }
        isRunning = true
        setRunUI(running: true)
        resetLog()
        items.append(.user(t))
        items.append(.assistant(text: "", tools: []))
        currentAssistant = items.count - 1
        render()
        runStart = Date()
        startClock()

        Task.detached { [weak self] in
            guard let self else { return }
            let record = await self.agent.send(t) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            await MainActor.run { [weak self] in
                self?.lastRecord = record
                self?.isRunning = false
                self?.currentAssistant = nil
                self?.setRunUI(running: false)
                self?.stopClock()
            }
        }
    }

    private func setRunUI(running: Bool) {
        sendButton.isEnabled = !running
        smokeButton.isEnabled = !running
        qaButton.isEnabled = !running
        clearButton.isEnabled = !running
    }

    // MARK: - events → chat model

    private func handle(_ event: RunEvent) {
        logLine(event.text)
        if isOrchestrating {
            handleOrchestration(event)
            render()
            return
        }
        switch event {
        case .task:
            break // already added the user bubble in send()
        case .text(let s):
            appendAssistantText(s)
        case .status(let s):
            appendAssistantText(s)
        case .toolCall(_, let name, let args):
            // Raw screenshot capture is hidden in the chat; the image_look card
            // shows the image + OCR instead.
            if name == "screenshot" { break }
            appendToolCard(ToolCard(name: name, arguments: args, result: nil, image: nil))
        case .toolResult(_, let name, let result):
            fillToolResult(name: name, result: result)
        case .screenshot(let url):
            screenshotURLs.append(url)
            // Image is rendered by the image_look card; no separate attach.
        case .timing(let step, let ttft, let tps, let tools):
            stepRows.append(StepRow(
                step: step,
                tools: tools.joined(separator: ","),
                ttft: ttft.map { String(format: "%.0fms", $0 * 1000) } ?? "—",
                tps: tps.map { String(format: "%.0f", $0) } ?? "—",
                tokensPerSecond: tps
            ))
            refreshStatus()
        case .finalAnswer(let s):
            let summary = extractSummary(s)
            appendAssistantText(summary)
        case .stopped:
            render()
        case .phase, .subagentStart, .subagentResult:
            break // only used in orchestration mode
        }
        render()
    }

    /// Orchestration rendering: phase + subagent lines in completion order, plus
    /// the synthesis final answer. Subagent-internal tool chatter is suppressed
    /// (it would interleave); timing + screenshots still feed Bench/Gallery.
    private func handleOrchestration(_ event: RunEvent) {
        switch event {
        case .phase(let p):
            appendAssistantText("── phase \(p) ──")
        case .subagentStart(let role, _):
            appendAssistantText("◷ spawn \(role)")
        case .subagentResult(let role, _, let answer, let ok):
            let mark = ok ? "✓" : "✗"
            appendAssistantText("\(mark) \(role) → \(answer)")
        case .timing(let step, let ttft, let tps, let tools):
            stepRows.append(StepRow(
                step: step,
                tools: tools.joined(separator: ","),
                ttft: ttft.map { String(format: "%.0fms", $0 * 1000) } ?? "—",
                tps: tps.map { String(format: "%.0f", $0) } ?? "—",
                tokensPerSecond: tps
            ))
            refreshStatus()
        case .screenshot(let url):
            screenshotURLs.append(url)
        case .finalAnswer(let s):
            appendAssistantText(extractSummary(s))
        case .stopped:
            render()
        case .task, .text, .status, .toolCall, .toolResult:
            break // suppress subagent chatter in orchestration mode
        }
    }

    // MARK: - logging (so the run can be inspected / debugged from disk)

    private static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cereaper/logs/latest.log")
    }

    private func resetLog() {
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data().write(to: url)
    }

    private func logLine(_ s: String) {
        let line = (s + "\n").data(using: .utf8) ?? Data()
        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        }
    }

    private func appendAssistantText(_ s: String) {
        guard let idx = currentAssistant, case .assistant(var text, let tools) = items[idx] else { return }
        if text.isEmpty { text = s } else { text += "\n" + s }
        items[idx] = .assistant(text: text, tools: tools)
    }

    private func appendToolCard(_ card: ToolCard) {
        guard let idx = currentAssistant, case .assistant(let text, var tools) = items[idx] else { return }
        tools.append(card)
        items[idx] = .assistant(text: text, tools: tools)
    }

    private func fillToolResult(name: String, result: String) {
        guard let idx = currentAssistant, case .assistant(let text, var tools) = items[idx] else { return }
        for i in tools.indices.indices.reversed() {
            if tools[i].name == name && tools[i].result == nil {
                tools[i].result = result
                break
            }
        }
        items[idx] = .assistant(text: text, tools: tools)
    }

    private func attachScreenshot(_ image: NSImage) {
        guard let idx = currentAssistant, case .assistant(let text, var tools) = items[idx] else { return }
        for i in tools.indices.reversed() {
            if tools[i].name == "screenshot" && tools[i].image == nil {
                tools[i].image = image
                break
            }
        }
        items[idx] = .assistant(text: text, tools: tools)
    }

    private func extractSummary(_ json: String) -> String {
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let s = obj["summary"] as? String { return s }
        return json
    }

    // MARK: - render

    private func render() {
        messageStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            messageStack.addArrangedSubview(row(for: item))
        }
        // scroll to bottom
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let h = self.messageStack.bounds.height
            let bottom = NSRect(x: 0, y: max(0, h - 1), width: 1, height: 1)
            self.messageScroll.contentView.scrollToVisible(bottom)
        }
    }

    private func row(for item: ChatItem) -> NSView {
        switch item {
        case .user(let text):
            return userRow(text)
        case .assistant(let text, let tools):
            return assistantRow(text: text, tools: tools)
        }
    }

    private func userRow(_ text: String) -> NSView {
        let bubble = wrappingLabel(text, font: Theme.textFont(), color: .white,
                                   maxWidth: bubbleMaxWidth, background: Theme.bubbleUser)
        bubble.layer?.cornerRadius = 12
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer, bubble])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func assistantRow(text: String, tools: [ToolCard]) -> NSView {
        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 8
        col.translatesAutoresizingMaskIntoConstraints = false

        let avatar = NSTextField(labelWithString: "✦ Cereaper")
        avatar.font = .systemFont(ofSize: 11, weight: .semibold)
        avatar.textColor = Theme.accent
        col.addArrangedSubview(avatar)

        if !text.isEmpty {
            let body = wrappingLabel(text, font: Theme.textFont(), color: Theme.text,
                                     maxWidth: bubbleMaxWidth, background: nil)
            col.addArrangedSubview(body)
        }
        for card in tools {
            col.addArrangedSubview(toolCardView(card))
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [col, spacer])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func toolCardView(_ card: ToolCard) -> NSView {
        // Screenshots render as a bare mini preview — no card chrome, no path text.
        if card.name == "screenshot", let image = card.image {
            let iv = NSImageView()
            iv.image = image
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.heightAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
            iv.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth).isActive = true
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 8
            iv.layer?.masksToBounds = true
            iv.layer?.borderColor = Theme.cardBorder.cgColor
            iv.layer?.borderWidth = 1
            return iv
        }

        // image_look renders as: mini image preview + OCR text panel.
        if card.name == "image_look" {
            return imageLookView(card)
        }

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.card.cgColor
        box.layer?.borderColor = Theme.cardBorder.cgColor
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: card.name)
        icon.contentTintColor = Theme.textSub
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let name = NSTextField(labelWithString: card.name)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = .white
        name.translatesAutoresizingMaskIntoConstraints = false

        let status = NSTextField(labelWithString: card.result == nil ? "running…" : "done")
        status.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        status.textColor = card.result == nil ? Theme.textDim : Theme.accent
        status.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [icon, name, NSView(), status])
        header.orientation = .horizontal
        header.spacing = 6
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        col.translatesAutoresizingMaskIntoConstraints = false
        col.addArrangedSubview(header)

        if !card.arguments.isEmpty, card.arguments != "{}" {
            let shown = card.arguments.count > 160
                ? String(card.arguments.prefix(160)) + " …" : card.arguments
            col.addArrangedSubview(codeLabel(shown, color: Theme.textSub))
        }
        if let result = card.result {
            col.addArrangedSubview(codeLabel(String(result.prefix(400)), color: Theme.textSub))
        }
        if let image = card.image {
            let iv = NSImageView()
            iv.image = image
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.heightAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
            iv.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth - 24).isActive = true
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 6
            iv.layer?.borderColor = Theme.cardBorder.cgColor
            iv.layer?.borderWidth = 1
            col.addArrangedSubview(iv)
        }

        box.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            col.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            col.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            col.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            box.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth),
        ])
        return box
    }

    /// image_look card: mini image preview + OCR text panel + dim description.
    private func imageLookView(_ card: ToolCard) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Parse the path from the tool arguments.
        var path: String?
        if let data = card.arguments.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            path = obj["path"] as? String
        }

        // Parse description + ocr from the result JSON.
        var description: String?
        var ocr: String?
        if let r = card.result, let data = r.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            description = obj["description"] as? String
            ocr = obj["ocr"] as? String
        }

        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        col.translatesAutoresizingMaskIntoConstraints = false
        col.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth).isActive = true

        // Mini image preview.
        if let p = path, let img = NSImage(contentsOf: URL(fileURLWithPath: p)) {
            let iv = NSImageView()
            iv.image = img
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.heightAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
            iv.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth).isActive = true
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 8
            iv.layer?.masksToBounds = true
            iv.layer?.borderColor = Theme.cardBorder.cgColor
            iv.layer?.borderWidth = 1
            col.addArrangedSubview(iv)
        }

        // OCR panel: bordered box with mono text.
        let ocrBox = NSView()
        ocrBox.translatesAutoresizingMaskIntoConstraints = false
        ocrBox.wantsLayer = true
        ocrBox.layer?.backgroundColor = Theme.card.cgColor
        ocrBox.layer?.borderColor = Theme.cardBorder.cgColor
        ocrBox.layer?.borderWidth = 1
        ocrBox.layer?.cornerRadius = 6

        let ocrHeader = NSTextField(labelWithString: "OCR")
        ocrHeader.translatesAutoresizingMaskIntoConstraints = false
        ocrHeader.font = .systemFont(ofSize: 9, weight: .semibold)
        ocrHeader.textColor = Theme.textDim

        let ocrText = NSTextField(labelWithString: "")
        ocrText.translatesAutoresizingMaskIntoConstraints = false
        ocrText.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        ocrText.textColor = Theme.textSub
        ocrText.lineBreakMode = .byWordWrapping
        ocrText.maximumNumberOfLines = 6
        ocrText.preferredMaxLayoutWidth = bubbleMaxWidth - 24
        ocrText.stringValue = {
            if let o = ocr, !o.isEmpty { return o }
            if card.result == nil { return "reading text…" }
            return "—"
        }()

        ocrBox.addSubview(ocrHeader)
        ocrBox.addSubview(ocrText)
        NSLayoutConstraint.activate([
            ocrHeader.topAnchor.constraint(equalTo: ocrBox.topAnchor, constant: 6),
            ocrHeader.leadingAnchor.constraint(equalTo: ocrBox.leadingAnchor, constant: 10),
            ocrText.topAnchor.constraint(equalTo: ocrBox.topAnchor, constant: 6),
            ocrText.leadingAnchor.constraint(equalTo: ocrBox.leadingAnchor, constant: 40),
            ocrText.trailingAnchor.constraint(equalTo: ocrBox.trailingAnchor, constant: -10),
            ocrText.bottomAnchor.constraint(equalTo: ocrBox.bottomAnchor, constant: -6),
            ocrBox.widthAnchor.constraint(lessThanOrEqualToConstant: bubbleMaxWidth),
        ])
        col.addArrangedSubview(ocrBox)

        // Dim description caption.
        if let d = description, !d.isEmpty {
            let cap = NSTextField(labelWithString: d)
            cap.translatesAutoresizingMaskIntoConstraints = false
            cap.font = .systemFont(ofSize: 10, weight: .regular)
            cap.textColor = Theme.textDim
            cap.lineBreakMode = .byTruncatingTail
            cap.maximumNumberOfLines = 2
            cap.preferredMaxLayoutWidth = bubbleMaxWidth - 8
            col.addArrangedSubview(cap)
        }

        container.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: container.topAnchor),
            col.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            col.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: - label helpers

    private func wrappingLabel(_ text: String, font: NSFont, color: NSColor,
                               maxWidth: CGFloat, background: NSColor?) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.stringValue = text
        l.font = font
        l.textColor = color
        l.lineBreakMode = .byWordWrapping
        l.cell?.truncatesLastVisibleLine = false
        l.cell?.wraps = true
        l.preferredMaxLayoutWidth = maxWidth - 24
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let bg = background {
            l.drawsBackground = true
            l.backgroundColor = bg
            l.wantsLayer = true
            // pad via the field's bezel-less inset
            l.cell?.backgroundStyle = .raised
        }
        return l
    }

    private func codeLabel(_ text: String, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.stringValue = text
        l.font = Theme.mono()
        l.textColor = color
        l.lineBreakMode = .byWordWrapping
        l.cell?.truncatesLastVisibleLine = false
        l.cell?.wraps = true
        l.preferredMaxLayoutWidth = bubbleMaxWidth - 48
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    // MARK: - status

    private func startClock() {
        stopClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }
    private func stopClock() { clockTimer?.invalidate(); clockTimer = nil }

    private func refreshStatus() {
        let axOn = AXPermission.check()
        let apiOn = ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"]?.isEmpty == false
        axDot.layer?.backgroundColor = (axOn ? NSColor.systemGreen : NSColor.systemRed).cgColor
        apiDot.layer?.backgroundColor = (apiOn ? NSColor.systemGreen : NSColor.systemRed).cgColor
        statusLeft.stringValue = axOn ? "AX trusted" : "AX not granted"
        statusRight.stringValue = apiOn ? "API key set" : "API key unset"

        let avgTps: Double = {
            let vals = stepRows.compactMap { $0.tokensPerSecond }
            guard !vals.isEmpty else { return 0 }
            return vals.reduce(0, +) / Double(vals.count)
        }()
        let wall = runStart.map { Date().timeIntervalSince($0) } ?? 0
        statusCenter.stringValue = String(format: "%d steps · avg %.0f tok/s · %.1fs",
                                          stepRows.count, avgTps, wall)
    }
}
