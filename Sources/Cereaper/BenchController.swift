import AppKit

/// Bench / telemetry view: headline summary numbers + a per-step tok/s bar chart
/// + a step-by-step table. Reads from the run controller's stepRows and record.
final class BenchController: NSObject {
    let view: NSView
    private let chart = BarChartView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let table: NSTableView
    private let scroll: NSScrollView
    private var rows: [StepRow] = []

    override init() {
        view = NSView()
        table = NSTableView()
        scroll = NSScrollView()
        super.init()
        build()
    }

    private func build() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let header = sectionHeader("TELEMETRY")

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        summaryLabel.textColor = .labelColor
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.preferredMaxLayoutWidth = 600

        let chartHeader = sectionHeader("TOKENS / SECOND PER STEP")
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let tableHeader = sectionHeader("STEP BREAKDOWN")
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 20
        table.backgroundColor = .clear
        let cols = [("step", 50), ("tools", 220), ("ttft", 80), ("tps", 100)]
        for (id, w) in cols {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.width = CGFloat(w); c.minWidth = CGFloat(w) * 0.5
            table.addTableColumn(c)
        }
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false

        view.addSubview(header)
        view.addSubview(summaryLabel)
        view.addSubview(chartHeader)
        view.addSubview(chart)
        view.addSubview(tableHeader)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            summaryLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            chartHeader.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 18),
            chartHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            chart.topAnchor.constraint(equalTo: chartHeader.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            chart.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableHeader.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 18),
            tableHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scroll.topAnchor.constraint(equalTo: tableHeader.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    func update(rows: [StepRow], record: RunRecord?) {
        self.rows = rows
        table.reloadData()

        let tps = rows.compactMap { $0.tokensPerSecond }
        let avg = tps.isEmpty ? 0 : tps.reduce(0, +) / Double(tps.count)
        let peak = tps.max() ?? 0
        let wall = record?.steps.compactMap { $0.totalSeconds }.reduce(0, +) ?? 0
        let outTokens = rows.compactMap { _ in 0 } // placeholder; record has totals
        let totalOut = record?.steps.compactMap { $0.completionTokens }.reduce(0, +) ?? 0
        let steps = rows.count
        let stopped = record?.stoppedReason ?? "—"

        summaryLabel.stringValue = String(
            format: "steps=%d  wall=%.2fs  avg=%.0f tok/s  peak=%.0f tok/s  outTokens=%d  stopped=%@",
            steps, wall, avg, peak, totalOut, stopped
        )

        chart.values = tps
        chart.needsDisplay = true
    }

    private func sectionHeader(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }
}

extension BenchController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let r = rows[row]
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
}

/// Simple bar chart drawn with Core Graphics. No external deps.
final class BarChartView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard !values.isEmpty else {
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let s = NSAttributedString(string: "No telemetry yet. Run the QA demo.", attributes: attr)
            s.draw(at: NSPoint(x: 12, y: 12))
            return
        }

        let maxVal = max(values.max() ?? 1, 1)
        let gap: CGFloat = 6
        let n = CGFloat(values.count)
        let barW = max((bounds.width - gap * (n + 1)) / n, 2)
        let chartH = bounds.height - 24

        for (i, v) in values.enumerated() {
            let h = CGFloat(v / maxVal) * chartH
            let x = gap + CGFloat(i) * (barW + gap)
            let r = NSRect(x: x, y: 0, width: barW, height: h)
            let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            NSColor.controlAccentColor.setFill()
            path.fill()

            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let label = NSAttributedString(string: String(format: "%.0f", v), attributes: attr)
            label.draw(at: NSPoint(x: x, y: h + 3))
        }
    }
}
