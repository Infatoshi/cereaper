import AppKit
import ApplicationServices

/// A single row in the steps table.
struct StepRow {
    let step: Int
    let tools: String
    let ttft: String
    let tps: String
    var tokensPerSecond: Double?
}

/// AppController owns the Cereaper window content: a three-pane layout
/// (sidebar · steps + transcript · screenshot + final answer) plus a live
/// status bar. UI only; all agent behavior lives in the Agent module.
final class AppController: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: surfaced for AppDelegate + sibling views
    let view: NSView
    private(set) var stepRows: [StepRow] = []
    private(set) var screenshotURLs: [URL] = []
    private(set) var lastRecord: RunRecord?

    // MARK: sidebar
    private let taskTextView: NSTextView
    private let taskScroll: NSScrollView
    private let runButton: NSButton
    private let stopButton: NSButton
    private let smokeButton: NSButton
    private let qaButton: NSButton
    private let axDot: NSView
    private let axLabel: NSTextField
    private let apiDot: NSView
    private let apiLabel: NSTextField
    private let modelLabel: NSTextField

    // MARK: center
    private let stepsTable: NSTableView
    private let stepsScroll: NSScrollView
    private let transcriptView: NSTextView
    private let transcriptScroll: NSScrollView

    // MARK: inspector
    private let screenshotView: NSImageView
    private let screenshotPlaceholder: NSTextField
    private let finalAnswerView: NSTextView
    private let finalAnswerScroll: NSScrollView

    // MARK: status bar
    private let statusLeft: NSTextField
    private let statusCenter: NSTextField
    private let statusRight: NSTextField

    // MARK: state
    private let agent = Agent()
    private var isRunning = false
    private var runStart: Date?
    private var clockTimer: Timer?

    override init() {
        taskTextView = NSTextView()
        taskScroll = NSScrollView()
        runButton = NSButton(title: "Run", target: nil, action: nil)
        stopButton = NSButton(title: "Stop", target: nil, action: nil)
        smokeButton = NSButton(title: "Smoke", target: nil, action: nil)
        qaButton = NSButton(title: "QA demo", target: nil, action: nil)
        axDot = NSView()
        axLabel = NSTextField(labelWithString: "")
        apiDot = NSView()
        apiLabel = NSTextField(labelWithString: "")
        modelLabel = NSTextField(labelWithString: "")
        stepsTable = NSTableView()
        stepsScroll = NSScrollView()
        transcriptView = NSTextView()
        transcriptScroll = NSScrollView()
        screenshotView = NSImageView()
        screenshotPlaceholder = NSTextField(labelWithString: "No screenshot yet")
        finalAnswerView = NSTextView()
        finalAnswerScroll = NSScrollView()
        statusLeft = NSTextField(labelWithString: "")
        statusCenter = NSTextField(labelWithString: "")
        statusRight = NSTextField(labelWithString: "")
        view = NSView()
        super.init()
        build()
        wire()
        refreshStatus()
    }

    // MARK: - build

    private func build() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.dividerStyle = .thin
        split.isVertical = true
        split.addSubview(sidebarView())
        split.addSubview(centerView())
        split.addSubview(inspectorView())
        split.setPosition(270, ofDividerAt: 0)

        let status = statusBar()

        view.addSubview(split)
        view.addSubview(status)

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: view.topAnchor),
            split.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: status.topAnchor),

            status.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    // MARK: sidebar

    private func sidebarView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let header = sectionHeader("TASK")
        configureEditor(taskTextView, placeholder: "Describe a desktop task for Cereaper…")
        taskTextView.font = .systemFont(ofSize: 13, weight: .regular)
        taskTextView.isRichText = false
        taskScroll.documentView = taskTextView
        taskScroll.hasVerticalScroller = true
        taskScroll.translatesAutoresizingMaskIntoConstraints = false
        taskScroll.drawsBackground = false
        taskScroll.borderType = .bezelBorder

        styleButton(runButton, emphasized: true)
        styleButton(stopButton, emphasized: false)
        stopButton.isEnabled = false
        styleButton(smokeButton, emphasized: false)
        styleButton(qaButton, emphasized: false)

        let presetRow = NSStackView(views: [smokeButton, qaButton])
        presetRow.orientation = .horizontal
        presetRow.spacing = 8
        presetRow.translatesAutoresizingMaskIntoConstraints = false

        let statusHeader = sectionHeader("STATUS")
        axDot.wantsLayer = true
        apiDot.wantsLayer = true
        axLabel.font = .systemFont(ofSize: 11)
        apiLabel.font = .systemFont(ofSize: 11)
        modelLabel.font = .systemFont(ofSize: 11)
        modelLabel.stringValue = "gemma-4-31b · reasoning: none"

        let axRow = statusRow(dot: axDot, label: axLabel)
        let apiRow = statusRow(dot: apiDot, label: apiLabel)

        container.addSubview(header)
        container.addSubview(taskScroll)
        container.addSubview(presetRow)
        container.addSubview(runButton)
        container.addSubview(stopButton)
        container.addSubview(statusHeader)
        container.addSubview(axRow)
        container.addSubview(apiRow)
        container.addSubview(modelLabel)

        let g = container.leadingAnchor
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: g, constant: 16),

            taskScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            taskScroll.leadingAnchor.constraint(equalTo: g, constant: 12),
            taskScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            taskScroll.heightAnchor.constraint(equalToConstant: 120),

            presetRow.topAnchor.constraint(equalTo: taskScroll.bottomAnchor, constant: 10),
            presetRow.leadingAnchor.constraint(equalTo: g, constant: 12),

            runButton.topAnchor.constraint(equalTo: presetRow.bottomAnchor, constant: 10),
            runButton.leadingAnchor.constraint(equalTo: g, constant: 12),
            runButton.widthAnchor.constraint(equalToConstant: 96),

            stopButton.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: runButton.trailingAnchor, constant: 8),

            statusHeader.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 18),
            statusHeader.leadingAnchor.constraint(equalTo: g, constant: 16),

            axRow.topAnchor.constraint(equalTo: statusHeader.bottomAnchor, constant: 6),
            axRow.leadingAnchor.constraint(equalTo: g, constant: 14),
            axRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            apiRow.topAnchor.constraint(equalTo: axRow.bottomAnchor, constant: 6),
            apiRow.leadingAnchor.constraint(equalTo: axRow.leadingAnchor),
            apiRow.trailingAnchor.constraint(equalTo: axRow.trailingAnchor),

            modelLabel.topAnchor.constraint(equalTo: apiRow.bottomAnchor, constant: 6),
            modelLabel.leadingAnchor.constraint(equalTo: g, constant: 14),
        ])

        return container
    }

    // MARK: center

    private func centerView() -> NSView {
        let container = NSView()
        let stepsHeader = sectionHeader("STEPS")

        stepsTable.dataSource = self
        stepsTable.delegate = self
        stepsTable.headerView = nil
        stepsTable.rowHeight = 22
        stepsTable.backgroundColor = .clear
        stepsTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let cols = ["step", "tools", "ttft", "tps"]
        let widths: [CGFloat] = [40, 150, 70, 80]
        for (i, id) in cols.enumerated() {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.width = widths[i]
            c.minWidth = widths[i] * 0.6
            stepsTable.addTableColumn(c)
        }
        stepsScroll.documentView = stepsTable
        stepsScroll.hasVerticalScroller = true
        stepsScroll.translatesAutoresizingMaskIntoConstraints = false
        stepsScroll.drawsBackground = false
        stepsScroll.borderType = .noBorder

        let transcriptHeader = sectionHeader("TRANSCRIPT")
        configureEditor(transcriptView, placeholder: "")
        transcriptView.isEditable = false
        transcriptView.isRichText = false
        transcriptView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        transcriptScroll.documentView = transcriptView
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.translatesAutoresizingMaskIntoConstraints = false
        transcriptScroll.drawsBackground = false

        container.addSubview(stepsHeader)
        container.addSubview(stepsScroll)
        container.addSubview(transcriptHeader)
        container.addSubview(transcriptScroll)

        let g = container.leadingAnchor
        NSLayoutConstraint.activate([
            stepsHeader.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stepsHeader.leadingAnchor.constraint(equalTo: g, constant: 14),

            stepsScroll.topAnchor.constraint(equalTo: stepsHeader.bottomAnchor, constant: 6),
            stepsScroll.leadingAnchor.constraint(equalTo: g, constant: 12),
            stepsScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stepsScroll.heightAnchor.constraint(equalToConstant: 168),

            transcriptHeader.topAnchor.constraint(equalTo: stepsScroll.bottomAnchor, constant: 14),
            transcriptHeader.leadingAnchor.constraint(equalTo: g, constant: 14),

            transcriptScroll.topAnchor.constraint(equalTo: transcriptHeader.bottomAnchor, constant: 6),
            transcriptScroll.leadingAnchor.constraint(equalTo: g, constant: 12),
            transcriptScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            transcriptScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }

    // MARK: inspector

    private func inspectorView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let shotHeader = sectionHeader("SCREENSHOT")
        screenshotView.imageScaling = .scaleProportionallyUpOrDown
        screenshotView.imageAlignment = .alignCenter
        screenshotView.wantsLayer = true
        screenshotView.layer?.borderColor = NSColor.separatorColor.cgColor
        screenshotView.layer?.borderWidth = 1
        screenshotView.translatesAutoresizingMaskIntoConstraints = false

        screenshotPlaceholder.font = .systemFont(ofSize: 12)
        screenshotPlaceholder.textColor = .secondaryLabelColor
        screenshotPlaceholder.alignment = .center
        screenshotPlaceholder.translatesAutoresizingMaskIntoConstraints = false

        let finalHeader = sectionHeader("FINAL ANSWER")
        configureEditor(finalAnswerView, placeholder: "")
        finalAnswerView.isEditable = false
        finalAnswerView.isRichText = false
        finalAnswerView.font = .systemFont(ofSize: 12, weight: .medium)
        finalAnswerScroll.documentView = finalAnswerView
        finalAnswerScroll.hasVerticalScroller = true
        finalAnswerScroll.translatesAutoresizingMaskIntoConstraints = false
        finalAnswerScroll.drawsBackground = false

        container.addSubview(shotHeader)
        container.addSubview(screenshotView)
        container.addSubview(screenshotPlaceholder)
        container.addSubview(finalHeader)
        container.addSubview(finalAnswerScroll)

        let g = container.leadingAnchor
        NSLayoutConstraint.activate([
            shotHeader.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            shotHeader.leadingAnchor.constraint(equalTo: g, constant: 14),

            screenshotView.topAnchor.constraint(equalTo: shotHeader.bottomAnchor, constant: 6),
            screenshotView.leadingAnchor.constraint(equalTo: g, constant: 12),
            screenshotView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            screenshotView.heightAnchor.constraint(equalTo: screenshotView.widthAnchor, multiplier: 0.62),

            screenshotPlaceholder.centerXAnchor.constraint(equalTo: screenshotView.centerXAnchor),
            screenshotPlaceholder.centerYAnchor.constraint(equalTo: screenshotView.centerYAnchor),

            finalHeader.topAnchor.constraint(equalTo: screenshotView.bottomAnchor, constant: 14),
            finalHeader.leadingAnchor.constraint(equalTo: g, constant: 14),

            finalAnswerScroll.topAnchor.constraint(equalTo: finalHeader.bottomAnchor, constant: 6),
            finalAnswerScroll.leadingAnchor.constraint(equalTo: g, constant: 12),
            finalAnswerScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            finalAnswerScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }

    // MARK: status bar

    private func statusBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        for l in [statusLeft, statusCenter, statusRight] {
            l.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            l.textColor = .secondaryLabelColor
            l.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(l)
        }
        statusLeft.alignment = .left
        statusCenter.alignment = .center
        statusRight.alignment = .right

        let top = NSView()
        top.translatesAutoresizingMaskIntoConstraints = false
        top.wantsLayer = true
        top.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bar.addSubview(top)

        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: bar.topAnchor),
            top.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 1),

            statusLeft.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusLeft.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            statusCenter.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusCenter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            statusRight.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusRight.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
        ])
        return bar
    }

    // MARK: - small view helpers

    private func sectionHeader(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func styleButton(_ b: NSButton, emphasized: Bool) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.bezelStyle = emphasized ? .regularSquare : .roundRect
        b.controlSize = .small
        if emphasized { b.keyEquivalent = "\r" }
    }

    private func configureEditor(_ tv: NSTextView, placeholder: String) {
        tv.isSelectable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.textBackgroundColor
    }

    private func statusRow(dot: NSView, label: NSTextField) -> NSStackView {
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        dot.layer?.cornerRadius = 4
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [dot, label])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func setDot(_ v: NSView, on: Bool) {
        v.layer?.backgroundColor = (on ? NSColor.systemGreen : NSColor.systemRed).cgColor
    }

    // MARK: - wiring

    private func wire() {
        runButton.target = self
        runButton.action = #selector(runTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        smokeButton.target = self
        smokeButton.action = #selector(smokeTapped)
        qaButton.target = self
        qaButton.action = #selector(qaTapped)
    }

    @objc func smokeTapped() {
        taskTextView.string = QAFlow.smokePrompt
    }

    @objc func qaTapped() {
        taskTextView.string = QAFlow.heroPrompt
    }

    @objc func stopTapped() {
        // Best-effort: the loop has no cancellation token yet; disable UI to signal intent.
        isRunning = false
        setRunUI(running: false)
        appendTranscript("▸ stop requested (current step will finish)")
    }

    @objc func runTapped() {
        guard !isRunning else { return }
        let task = taskTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        startRun(task: task)
    }

    @objc func clearTapped() {
        stepRows.removeAll()
        screenshotURLs.removeAll()
        lastRecord = nil
        stepsTable.reloadData()
        transcriptView.string = ""
        finalAnswerView.string = ""
        screenshotView.image = nil
        screenshotPlaceholder.isHidden = false
        statusCenter.stringValue = ""
    }

    @objc func permissionsTapped() {
        AXPermission.request()
        refreshStatus()
    }

    // MARK: - run

    private func startRun(task: String) {
        isRunning = true
        setRunUI(running: true)
        stepRows.removeAll()
        screenshotURLs.removeAll()
        lastRecord = nil
        stepsTable.reloadData()
        transcriptView.string = ""
        finalAnswerView.string = ""
        screenshotView.image = nil
        screenshotPlaceholder.isHidden = false
        runStart = Date()
        startClock()

        Task.detached { [weak self] in
            guard let self else { return }
            let record = await self.agent.run(task: task) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            await MainActor.run { [weak self] in
                self?.lastRecord = record
                self?.isRunning = false
                self?.setRunUI(running: false)
                self?.stopClock()
                self?.appendTranscript("▸ done")
            }
        }
    }

    private func setRunUI(running: Bool) {
        runButton.isEnabled = !running
        stopButton.isEnabled = running
        smokeButton.isEnabled = !running
        qaButton.isEnabled = !running
    }

    // MARK: - events

    private func handle(_ event: RunEvent) {
        switch event {
        case .task(let t):
            appendTranscript("▸ task: \(t)")
        case .text(let s):
            appendTranscript(s)
        case .status(let s):
            appendTranscript(s)
        case .toolCall(_, let n, let a):
            appendTranscript("  → \(n)(\(a))")
        case .toolResult(_, let n, let r):
            appendTranscript("  ← \(n): \(r)")
        case .timing(let step, let ttft, let tps, let tools):
            let row = StepRow(
                step: step,
                tools: tools.joined(separator: ","),
                ttft: ttft.map { String(format: "%.0fms", $0 * 1000) } ?? "—",
                tps: tps.map { String(format: "%.0f", $0) } ?? "—",
                tokensPerSecond: tps
            )
            stepRows.append(row)
            stepsTable.reloadData()
            let last = stepRows.count - 1
            if last >= 0 { stepsTable.scrollRowToVisible(last) }
            refreshStatus()
        case .screenshot(let url):
            screenshotURLs.append(url)
            if let img = NSImage(contentsOf: url) {
                screenshotView.image = img
                screenshotPlaceholder.isHidden = true
            }
        case .finalAnswer(let s):
            finalAnswerView.string = s
        case .stopped(let s):
            appendTranscript("▸ stopped: \(s)")
        }
    }

    // MARK: - table view

    func numberOfRows(in tableView: NSTableView) -> Int { stepRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < stepRows.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let r = stepRows[row]
        let cell = NSTableCellView()
        let tf = NSTextField(labelWithString: "")
        tf.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        switch id {
        case "step": tf.stringValue = "\(r.step)"; tf.textColor = .tertiaryLabelColor
        case "tools": tf.stringValue = r.tools
        case "ttft": tf.stringValue = r.ttft; tf.textColor = .secondaryLabelColor
        case "tps": tf.stringValue = r.tps + " tok/s"; tf.textColor = .systemBlue
        default: tf.stringValue = ""
        }
        return cell
    }

    // MARK: - transcript / status

    private func appendTranscript(_ line: String) {
        let attr = NSMutableAttributedString(string: line + "\n")
        attr.addAttribute(.font,
                         value: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                         range: NSRange(location: 0, length: attr.length))
        transcriptView.textStorage?.append(attr)
        transcriptView.scrollToEndOfDocument(nil)
    }

    private func startClock() {
        stopClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }
    private func stopClock() {
        clockTimer?.invalidate(); clockTimer = nil
    }

    private func refreshStatus() {
        let axOn = AXPermission.check()
        let apiOn = ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"]?.isEmpty == false
        setDot(axDot, on: axOn)
        setDot(apiDot, on: apiOn)
        axLabel.stringValue = axOn ? "Accessibility trusted" : "Accessibility not granted"
        apiLabel.stringValue = apiOn ? "Cerebras API key set" : "CEREBRAS_API_KEY unset"

        statusLeft.stringValue = "gemma-4-31b · reasoning: none"
        let avgTps: Double = {
            let vals = stepRows.compactMap { $0.tokensPerSecond }
            guard !vals.isEmpty else { return 0 }
            return vals.reduce(0, +) / Double(vals.count)
        }()
        let wall = runStart.map { Date().timeIntervalSince($0) } ?? 0
        statusCenter.stringValue = String(format: "avg %.0f tok/s · %d steps · %.1fs", avgTps, stepRows.count, wall)
        statusRight.stringValue = axOn && apiOn ? "ready" : "needs setup"
    }
}
