import AppKit

/// Screenshots gallery: every screenshot the agent captured during a run, as
/// thumbnails with the capture index. Rebuilds on each visit from the run
/// controller's screenshotURLs.
final class ScreenshotsController: NSObject {
    let view: NSView

    private let scroll: NSScrollView
    private let stack: NSStackView
    private let placeholder: NSTextField

    override init() {
        view = NSView()
        scroll = NSScrollView()
        stack = NSStackView()
        placeholder = NSTextField(labelWithString: "No screenshots captured yet.\nRun the QA demo to populate this gallery.")
        super.init()
        build()
    }

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.font = .systemFont(ofSize: 13)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.alignment = .center

        let header = sectionHeader("CAPTURED SCREENSHOTS")

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.addSubview(header)
        view.addSubview(scroll)
        view.addSubview(placeholder)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func update(urls: [URL]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        placeholder.isHidden = !urls.isEmpty

        for (i, url) in urls.enumerated() {
            guard let img = NSImage(contentsOf: url) else { continue }
            let cell = screenshotCell(index: i + 1, image: img, url: url)
            stack.addArrangedSubview(cell)
        }
    }

    private func screenshotCell(index: Int, image: NSImage, url: URL) -> NSView {
        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false

        let iv = NSImageView()
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
        iv.wantsLayer = true
        iv.layer?.borderColor = NSColor.separatorColor.cgColor
        iv.layer?.borderWidth = 1
        iv.layer?.cornerRadius = 4
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.heightAnchor.constraint(equalToConstant: 200).isActive = true
        iv.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let label = NSTextField(labelWithString: "Screenshot \(index)")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)

        let path = NSTextField(labelWithString: url.lastPathComponent)
        path.translatesAutoresizingMaskIntoConstraints = false
        path.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        path.textColor = .tertiaryLabelColor

        let meta = NSTextField(labelWithString: "\(Int(image.size.width))×\(Int(image.size.height))")
        meta.translatesAutoresizingMaskIntoConstraints = false
        meta.font = .systemFont(ofSize: 10)
        meta.textColor = .secondaryLabelColor

        cell.addSubview(iv)
        cell.addSubview(label)
        cell.addSubview(path)
        cell.addSubview(meta)

        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: cell.topAnchor),
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            iv.bottomAnchor.constraint(equalTo: cell.bottomAnchor),

            label.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: iv.topAnchor, constant: 4),

            path.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            path.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),

            meta.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            meta.topAnchor.constraint(equalTo: path.bottomAnchor, constant: 4),
        ])
        return cell
    }

    private func sectionHeader(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }
}
