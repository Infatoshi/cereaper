import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let appController = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1080, height: 680)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cereaper"
        window.titlebarAppearsTransparent = false
        window.center()
        window.contentView = appController.view
        window.minSize = NSSize(width: 880, height: 540)
        window.makeKeyAndOrderFront(nil)

        let toolbar = NSToolbar(identifier: "cereaper.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        self.window = window
        installMenus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMenus() {
        let main = NSApp.mainMenu
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Clear", action: #selector(AppController.clearTapped), keyEquivalent: "k")
        main?.addItem(edit)
    }
}

extension AppDelegate: NSToolbarDelegate {
    private enum Item: String {
        case run, stop, smoke, qa, clear, permissions, space
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.run, .stop, .smoke, .qa, .space, .clear, .permissions].map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.run, .stop, .smoke, .qa, .space, .clear, .permissions].map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier.rawValue {
        case "run":
            item.label = "Run"; item.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")
            item.action = #selector(AppController.runTapped)
        case "stop":
            item.label = "Stop"; item.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
            item.action = #selector(AppController.stopTapped)
        case "smoke":
            item.label = "Smoke"; item.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Smoke")
            item.action = #selector(AppController.smokeTapped)
        case "qa":
            item.label = "QA demo"; item.image = NSImage(systemSymbolName: "ant", accessibilityDescription: "QA demo")
            item.action = #selector(AppController.qaTapped)
        case "clear":
            item.label = "Clear"; item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")
            item.action = #selector(AppController.clearTapped)
        case "permissions":
            item.label = "Permissions"; item.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Permissions")
            item.action = #selector(AppController.permissionsTapped)
        case "space":
            return NSToolbarItem(itemIdentifier: .space)
        default:
            return nil
        }
        item.target = appController
        item.isBordered = true
        return item
    }
}
