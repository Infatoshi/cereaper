import AppKit

/// WorkspaceController is the window's root: a macOS-style navigation rail on the
/// left (Run · Screenshots · Bench · Settings) and a content area that swaps the
/// active destination's view. The Run destination is AppController (the agent
/// runner); the others read shared state from it.
final class WorkspaceController: NSObject {
    let view: NSView
    let runController = AppController()

    private enum Destination: String, CaseIterable {
        case run, screenshots, bench, settings
        var title: String {
            switch self {
            case .run: return "Run"
            case .screenshots: return "Screenshots"
            case .bench: return "Bench"
            case .settings: return "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .run: return "play.rectangle"
            case .screenshots: return "photo.on.rectangle"
            case .bench: return "chart.bar"
            case .settings: return "gearshape"
            }
        }
    }

    private var railButtons: [Destination: NSButton] = [:]
    private let contentContainer: NSView
    private let screenshotsController: ScreenshotsController
    private let benchController: BenchController
    private let settingsController: SettingsController
    private var current: Destination = .run
    private var currentView: NSView?

    override init() {
        contentContainer = NSView()
        screenshotsController = ScreenshotsController()
        benchController = BenchController()
        settingsController = SettingsController()
        view = NSView()
        super.init()
        build()
        select(.run)
    }

    private func build() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let rail = railView()
        rail.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor

        view.addSubview(rail)
        view.addSubview(divider)
        view.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            rail.topAnchor.constraint(equalTo: view.topAnchor),
            rail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: 176),

            divider.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            contentContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: rail

    private func railView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let wordmark = NSTextField(labelWithString: "Cereaper")
        wordmark.translatesAutoresizingMaskIntoConstraints = false
        wordmark.font = .systemFont(ofSize: 15, weight: .semibold)
        wordmark.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "desktop agent")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = .systemFont(ofSize: 10, weight: .regular)
        subtitle.textColor = .tertiaryLabelColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)

        for d in Destination.allCases {
            let b = railButton(d)
            railButtons[d] = b
            stack.addArrangedSubview(b)
            b.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
        stack.addArrangedSubview(spacer)

        container.addSubview(wordmark)
        container.addSubview(subtitle)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            wordmark.topAnchor.constraint(equalTo: container.topAnchor, constant: 38),
            wordmark.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            subtitle.topAnchor.constraint(equalTo: wordmark.bottomAnchor, constant: 1),
            subtitle.leadingAnchor.constraint(equalTo: wordmark.leadingAnchor),

            stack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        ])

        return container
    }

    private func railButton(_ d: Destination) -> NSButton {
        let b = NSButton()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.bezelStyle = .roundRect
        b.controlSize = .regular
        b.isBordered = false
        b.imagePosition = .imageLeading
        b.contentTintColor = .secondaryLabelColor
        b.title = "  \(d.title)"
        b.image = NSImage(systemSymbolName: d.symbol, accessibilityDescription: d.title)
        b.font = .systemFont(ofSize: 13, weight: .medium)
        b.alignment = .left
        b.target = self
        b.action = #selector(railTapped(_:))
        b.tag = Destination.allCases.firstIndex(of: d)!
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    @objc private func railTapped(_ sender: NSButton) {
        guard let d = Destination.allCases[safe: sender.tag] else { return }
        select(d)
    }

    // MARK: content swap

    private func select(_ d: Destination) {
        current = d
        for (dest, btn) in railButtons {
            let on = dest == d
            btn.isHighlighted = on
            btn.contentTintColor = on ? .controlAccentColor : .secondaryLabelColor
            btn.font = on ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13, weight: .medium)
        }

        currentView?.removeFromSuperview()
        let v: NSView
        switch d {
        case .run:
            v = runController.view
        case .screenshots:
            screenshotsController.update(urls: runController.screenshotURLs)
            v = screenshotsController.view
        case .bench:
            benchController.update(rows: runController.stepRows, record: runController.lastRecord)
            v = benchController.view
        case .settings:
            settingsController.refresh()
            v = settingsController.view
        }
        v.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            v.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentView = v
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
