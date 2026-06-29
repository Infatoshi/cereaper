import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Native macOS accessibility computer-use. Grounded and fail-closed: actions
/// target real AX elements by index in the frontmost window's tree, never guessed
/// coordinates. Inspired by tau-computer-use's posture, but uses the AX API
/// directly instead of osascript.
///
/// REQUIREMENT: the app must be granted Accessibility permission in
/// System Settings > Privacy & Security > Accessibility. `AXPermission.check()`
/// reports status; `AXPermission.request()` prompts once.
enum AXPermission {
    static func check() -> Bool { AXIsProcessTrusted() }
    static func request() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

/// A flattened, index-addressable view of an AX element tree for grounding.
struct AXNode: Codable {
    let index: Int
    let role: String
    let title: String?
    let value: String?
    let enabled: Bool?
    let frame: String? // "x,y,w,h"
    let children: [AXNode]
}

/// Our own error type (renamed to avoid colliding with the C `AXError` enum).
enum CereaperAXError: Error {
    case appNotFound(String)
    case noFocusedWindow
    case indexNotFound(Int)
    case actionFailed(String, Int32)
    case unknownKey(String)
}

enum AXGround {
    /// Activate an already-running app by name and return its AX application element.
    /// Fail-closed: if the app isn't running, throw (launch it via bash first).
    static func focusApp(_ name: String) throws -> AXUIElement {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var app: NSRunningApplication?
        for a in apps {
            if let local = a.localizedName, local.lowercased() == name.lowercased() {
                app = a; break
            }
        }
        guard let running = app else { throw CereaperAXError.appNotFound(name) }
        running.activate(options: [.activateIgnoringOtherApps])
        Thread.sleep(forTimeInterval: 0.4)
        let appEl = AXUIElementCreateApplication(running.processIdentifier)
        // Nudge it to frontmost via AX too (background-launched apps often don't
        // grab focus, which leaves kAXFocusedWindowAttribute empty).
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue as CFTypeRef)
        Thread.sleep(forTimeInterval: 0.2)
        return appEl
    }

    /// Build a bounded tree of the frontmost window of an app element. Falls back
    /// to the first window in kAXWindowsAttribute if no window reports as focused.
    static func frontmostWindowTree(_ app: AXUIElement, maxDepth: Int = 5, maxChildren: Int = 40) throws -> AXNode {
        var windowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef)
        if windowRef == nil {
            // Fall back to the windows list.
            var windowsRef: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
            if let arr = windowsRef as? [AXUIElement], let first = arr.first {
                windowRef = first
            }
        }
        guard windowRef != nil else { throw CereaperAXError.noFocusedWindow }
        let window = windowRef as! AXUIElement
        var counter = 0
        return buildNode(window, depth: 0, maxDepth: maxDepth, maxChildren: maxChildren, counter: &counter)
    }

    /// Flatten the tree into a list of (index -> path) for action dispatch.
    static func flatten(_ node: AXNode) -> [(Int, AXPath)] {
        var out: [(Int, AXPath)] = []
        walk(node, path: [], out: &out)
        return out
    }

    // MARK: - actions

    static func press(_ app: AXUIElement, index: Int) throws {
        let tree = try frontmostWindowTree(app)
        let flat = flatten(tree)
        guard let entry = flat.first(where: { $0.0 == index }) else { throw CereaperAXError.indexNotFound(index) }
        let el = resolve(app, path: entry.1)
        let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
        if err != .success { throw CereaperAXError.actionFailed("press", err.rawValue) }
    }

    static func setValue(_ app: AXUIElement, index: Int, value: String) throws {
        let tree = try frontmostWindowTree(app)
        let flat = flatten(tree)
        guard let entry = flat.first(where: { $0.0 == index }) else { throw CereaperAXError.indexNotFound(index) }
        let el = resolve(app, path: entry.1)
        // Strings are passed as CFString directly (AXValue is for point/size/rect/range).
        let err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, value as CFTypeRef)
        if err != .success { throw CereaperAXError.actionFailed("set_value", err.rawValue) }
    }

    /// Type text into the focused element via CGEvent.
    static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            var units: [UInt16] = [UInt16(scalar.value & 0xFFFF)]
            units.withUnsafeBufferPointer { buf in
                down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: buf.baseAddress!)
                up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: buf.baseAddress!)
            }
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    static func pressKey(_ name: String) throws {
        guard let code = KeyMap[name.lowercased()] else { throw CereaperAXError.unknownKey(name) }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - internals

    private static func buildNode(_ element: AXUIElement, depth: Int, maxDepth: Int,
                                  maxChildren: Int, counter: inout Int) -> AXNode {
        let idx = counter
        counter += 1
        let role = stringAttr(element, kAXRoleAttribute) ?? "?"
        let title = stringAttr(element, kAXTitleAttribute)
        let value = stringAttr(element, kAXValueAttribute)
        let enabled = boolAttr(element, kAXEnabledAttribute)
        let frame = frameString(element)

        var children: [AXNode] = []
        if depth < maxDepth {
            if let kids = childrenRefs(element) {
                for child in kids.prefix(maxChildren) {
                    children.append(buildNode(child, depth: depth + 1, maxDepth: maxDepth,
                                              maxChildren: maxChildren, counter: &counter))
                }
            }
        }
        return AXNode(index: idx, role: role, title: title, value: value,
                      enabled: enabled, frame: frame, children: children)
    }

    private static func walk(_ node: AXNode, path: AXPath, out: inout [(Int, AXPath)]) {
        out.append((node.index, path))
        for (pos, child) in node.children.enumerated() {
            // Path uses the child's ARRAY POSITION within its parent's children,
            // NOT its preorder index — resolve() indexes children by position.
            walk(child, path: path + [pos], out: &out)
        }
    }

    /// Path of child indices from the focused window down to the target element.
    typealias AXPath = [Int]

    private static func resolve(_ app: AXUIElement, path: AXPath) -> AXUIElement {
        var windowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef)
        if windowRef == nil {
            var windowsRef: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
            if let arr = windowsRef as? [AXUIElement], let first = arr.first {
                windowRef = first
            }
        }
        guard windowRef != nil else { return app }
        var current = windowRef as! AXUIElement
        for idx in path {
            let kids = childrenRefs(current) ?? []
            if idx < kids.count { current = kids[idx] }
        }
        return current
    }

    private static func stringAttr(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attr as CFString, &ref)
        if let s = ref as? String { return s }
        if let n = ref as? NSNumber { return n.stringValue }
        return nil
    }
    private static func boolAttr(_ el: AXUIElement, _ attr: String) -> Bool? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attr as CFString, &ref)
        return (ref as? NSNumber)?.boolValue
    }
    private static func childrenRefs(_ el: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref)
        return ref as? [AXUIElement]
    }
    private static func frameString(_ el: AXUIElement) -> String? {
        var posRef: CFTypeRef?; var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef)
        guard posRef != nil, sizeRef != nil else { return nil }
        let p = posRef as! AXValue
        let s = sizeRef as! AXValue
        var pt = CGPoint.zero; var sz = CGSize.zero
        AXValueGetValue(p, .cgPoint, &pt)
        AXValueGetValue(s, .cgSize, &sz)
        return String(format: "%.0f,%.0f,%.0f,%.0f", pt.x, pt.y, sz.width, sz.height)
    }
}

let KeyMap: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53,
    "delete": 51, "up": 126, "down": 125, "left": 123, "right": 124,
    "cmd": 55, "shift": 56, "ctrl": 59, "opt": 58, "a": 0, "c": 8, "v": 9,
    "x": 7, "l": 37, "t": 17, "w": 13, "r": 15, "n": 45, "f": 3,
]
