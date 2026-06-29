import AppKit

// Cereaper — native macOS entry point.
// The App module owns the window; the Agent module owns the loop.
// Keep this file small: wire NSApplication, build the window, hand off to App.

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
