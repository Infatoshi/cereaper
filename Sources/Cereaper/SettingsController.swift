import AppKit
import ApplicationServices

/// Settings view: API key + AX permission status, model, reasoning effort,
/// step budget, and a permissions button. Reads live state on each visit.
final class SettingsController: NSObject {
    let view: NSView
    private let axDot = NSView()
    private let axLabel = NSTextField(labelWithString: "")
    private let apiDot = NSView()
    private let apiLabel = NSTextField(labelWithString: "")
    private let modelField = NSTextField(labelWithString: "gemma-4-31b")
    private let reasoningField = NSTextField(labelWithString: "none (action) · high (verify)")
    private let stepsField = NSTextField(labelWithString: "24")
    private let permsButton = NSButton(title: "Request Accessibility…", target: nil, action: nil)

    override init() {
        view = NSView()
        super.init()
        build()
    }

    private func build() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = sectionHeader("SETTINGS")

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false

        let axRow = dotRow(dot: axDot, label: axLabel)
        let apiRow = dotRow(dot: apiDot, label: apiLabel)

        permsButton.translatesAutoresizingMaskIntoConstraints = false
        permsButton.bezelStyle = .roundRect
        permsButton.controlSize = .small
        permsButton.target = self
        permsButton.action = #selector(permsTapped)

        let modelRow = kvRow("Model", modelField)
        let reasoningRow = kvRow("Reasoning", reasoningField)
        let stepsRow = kvRow("Step budget", stepsField)

        card.addSubview(axRow)
        card.addSubview(apiRow)
        card.addSubview(permsButton)
        card.addSubview(modelRow)
        card.addSubview(reasoningRow)
        card.addSubview(stepsRow)

        let g = card.leadingAnchor
        NSLayoutConstraint.activate([
            axRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            axRow.leadingAnchor.constraint(equalTo: g, constant: 16),
            axRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            apiRow.topAnchor.constraint(equalTo: axRow.bottomAnchor, constant: 10),
            apiRow.leadingAnchor.constraint(equalTo: axRow.leadingAnchor),
            apiRow.trailingAnchor.constraint(equalTo: axRow.trailingAnchor),

            permsButton.topAnchor.constraint(equalTo: apiRow.bottomAnchor, constant: 12),
            permsButton.leadingAnchor.constraint(equalTo: axRow.leadingAnchor),

            modelRow.topAnchor.constraint(equalTo: permsButton.bottomAnchor, constant: 18),
            modelRow.leadingAnchor.constraint(equalTo: axRow.leadingAnchor),
            modelRow.trailingAnchor.constraint(equalTo: axRow.trailingAnchor),

            reasoningRow.topAnchor.constraint(equalTo: modelRow.bottomAnchor, constant: 10),
            reasoningRow.leadingAnchor.constraint(equalTo: axRow.leadingAnchor),
            reasoningRow.trailingAnchor.constraint(equalTo: axRow.trailingAnchor),

            stepsRow.topAnchor.constraint(equalTo: reasoningRow.bottomAnchor, constant: 10),
            stepsRow.leadingAnchor.constraint(equalTo: axRow.leadingAnchor),
            stepsRow.trailingAnchor.constraint(equalTo: axRow.trailingAnchor),
            stepsRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        view.addSubview(title)
        view.addSubview(card)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            card.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    func refresh() {
        let axOn = AXPermission.check()
        let apiOn = ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"]?.isEmpty == false
        setDot(axDot, on: axOn)
        setDot(apiDot, on: apiOn)
        axLabel.stringValue = axOn ? "Accessibility trusted" : "Accessibility not granted"
        apiLabel.stringValue = apiOn ? "Cerebras API key set" : "CEREBRAS_API_KEY unset"
    }

    @objc private func permsTapped() {
        AXPermission.request()
        refresh()
    }

    private func setDot(_ v: NSView, on: Bool) {
        v.wantsLayer = true
        v.layer?.backgroundColor = (on ? NSColor.systemGreen : NSColor.systemRed).cgColor
        v.layer?.cornerRadius = 4
    }

    private func dotRow(dot: NSView, label: NSTextField) -> NSStackView {
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        let row = NSStackView(views: [dot, label])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func kvRow(_ key: String, _ value: NSTextField) -> NSView {
        let k = NSTextField(labelWithString: key)
        k.translatesAutoresizingMaskIntoConstraints = false
        k.font = .systemFont(ofSize: 12, weight: .medium)
        k.textColor = .secondaryLabelColor
        value.translatesAutoresizingMaskIntoConstraints = false
        value.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let row = NSStackView(views: [k, NSView(), value])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func sectionHeader(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }
}
