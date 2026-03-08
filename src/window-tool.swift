import AVFoundation
import Cocoa
import Foundation
import ScreenCaptureKit

let VERSION = "0.6.0"

// MARK: - Configuration

struct Config {
    var bundleId: String = "com.googlecode.iterm2"
    var jsonOutput: Bool = false
}

var config = Config()

func printJSON(_ value: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        fputs("Error: Failed to serialize JSON output\n", stderr)
        exit(1)
    }
    print(str)
}

// MARK: - Errors

enum WindowToolError: LocalizedError {
    case appNotFound(String)
    case ambiguousApp(query: String, matches: [(name: String, bundleId: String)])
    case windowIndexOutOfRange(index: Int, count: Int)
    case noWindowMatchingTitle(String)
    case noWindowMatchingID(CGWindowID)
    case screenIndexOutOfRange(index: Int, count: Int)
    case accessibilityNotEnabled
    case invalidArgument(value: String, label: String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let id):
            return "Application not found: \(id)"
        case .ambiguousApp(let query, let matches):
            let list = matches.map { "  \($0.name) (\($0.bundleId))" }.joined(separator: "\n")
            return "Multiple apps match '\(query)':\n\(list)\nUse a more specific name or the full bundle ID."
        case .windowIndexOutOfRange(let index, let count):
            return "Window index \(index) out of range\(count == 0 ? " (no windows)" : " (0..\(count - 1))")"
        case .noWindowMatchingTitle(let pattern):
            return "No window found matching '\(pattern)'"
        case .noWindowMatchingID(let windowID):
            return "No window found with ID \(windowID)"
        case .screenIndexOutOfRange(let index, let count):
            return "Screen index \(index) out of range (0..\(count - 1))"
        case .accessibilityNotEnabled:
            return "Accessibility access is not enabled.\nGrant access in System Settings > Privacy & Security > Accessibility.\nAdd this terminal app or the window-tool binary."
        case .invalidArgument(let value, let label):
            return "'\(value)' is not a valid \(label)"
        }
    }
}

// MARK: - Argument Parsing Helpers

func parseInt(_ s: String, label: String) throws -> Int {
    guard let v = Int(s) else {
        throw WindowToolError.invalidArgument(value: s, label: label)
    }
    return v
}

func parseDouble(_ s: String, label: String) throws -> Double {
    guard let v = Double(s) else {
        throw WindowToolError.invalidArgument(value: s, label: label)
    }
    return v
}

// MARK: - Color Parsing

let validColors = ["red", "green", "blue", "yellow", "orange", "purple", "white", "cyan", "magenta", "random"]

func parseColor(_ name: String) throws -> NSColor {
    switch name.lowercased() {
    case "red": return .red
    case "green": return .green
    case "blue": return .blue
    case "yellow": return .yellow
    case "orange": return .orange
    case "purple": return .purple
    case "white": return .white
    case "cyan": return .cyan
    case "magenta": return .magenta
    case "random":
        let colors: [NSColor] = [.red, .green, .blue, .yellow, .orange, .purple, .white, .cyan, .magenta]
        return colors[Int.random(in: 0..<colors.count)]
    default:
        throw WindowToolError.invalidArgument(value: name, label: "color (valid: \(validColors.joined(separator: ", ")))")
    }
}

func parseFlashFlags(_ args: inout [String]) throws -> (color: NSColor, count: Int) {
    var color = NSColor.green
    var count = 1
    if let colorIdx = args.firstIndex(of: "--color") {
        guard colorIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--color", label: "flag (requires a value)")
        }
        color = try parseColor(args[colorIdx + 1])
        args.removeSubrange(colorIdx...colorIdx + 1)
    }
    if let countIdx = args.firstIndex(of: "--count") {
        guard countIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--count", label: "flag (requires a value)")
        }
        count = try parseInt(args[countIdx + 1], label: "count")
        args.removeSubrange(countIdx...countIdx + 1)
    }
    return (color, count)
}

func parseHighlightFlags(_ args: [String]) throws -> (color: NSColor, duration: Double) {
    var color: NSColor = .red
    var duration: Double = 3.0
    if let colorIdx = args.firstIndex(of: "--color") {
        guard colorIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--color", label: "flag (requires a value)")
        }
        color = try parseColor(args[colorIdx + 1])
    }
    if let durIdx = args.firstIndex(of: "--duration") {
        guard durIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--duration", label: "flag (requires a value)")
        }
        duration = try parseDouble(args[durIdx + 1], label: "duration")
    }
    return (color, duration)
}

func parseBorderFlags(_ args: [String]) throws -> (color: NSColor, width: CGFloat) {
    var color: NSColor = .blue
    var width: CGFloat = 3
    if let colorIdx = args.firstIndex(of: "--color") {
        guard colorIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--color", label: "flag (requires a value)")
        }
        color = try parseColor(args[colorIdx + 1])
    }
    if let widthIdx = args.firstIndex(of: "--width") {
        guard widthIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--width", label: "flag (requires a value)")
        }
        width = CGFloat(try parseDouble(args[widthIdx + 1], label: "width"))
    }
    return (color, width)
}

// MARK: - Accessibility Helpers

/// Resolves an app identifier to a bundle ID.
/// If the identifier contains a dot, it's treated as an exact bundle ID.
/// Otherwise, it's matched case-insensitively against app names and bundle IDs of running apps.
func resolveAppIdentifier(_ identifier: String) throws -> String {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

    // Try exact bundle ID match first
    if apps.contains(where: { $0.bundleIdentifier == identifier }) {
        return identifier
    }

    // Fuzzy match against app names and bundle IDs
    let query = identifier.lowercased()
    var matches: [(name: String, bundleId: String)] = []
    var seen = Set<String>()
    for app in apps {
        guard let bundleId = app.bundleIdentifier, !seen.contains(bundleId) else { continue }
        seen.insert(bundleId)
        let name = app.localizedName ?? ""
        if name.lowercased().contains(query) || bundleId.lowercased().contains(query) {
            matches.append((name: name, bundleId: bundleId))
        }
    }
    if matches.count == 1 {
        return matches[0].bundleId
    } else if matches.count > 1 {
        throw WindowToolError.ambiguousApp(query: identifier, matches: matches)
    }
    throw WindowToolError.appNotFound(identifier)
}

/// Returns the AXUIElement for a running application matching the given bundle identifier.
/// Returns nil if no running application with that bundle ID is found.
func getAppElement(bundleId: String) -> AXUIElement? {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    guard let app = apps.first else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

/// Returns the CGWindowID for an AXUIElement window, or nil if unavailable.
func getCGWindowID(_ element: AXUIElement) -> CGWindowID? {
    var windowID: CGWindowID = 0
    let result = _AXUIElementGetWindow(element, &windowID)
    return result == .success ? windowID : nil
}

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Holds metadata about a single window retrieved via the Accessibility API.
struct WindowInfo {
    /// The underlying AXUIElement handle for this window.
    let element: AXUIElement
    /// The zero-based index of the window in the application's window list.
    let id: Int
    /// The window's title (may be empty).
    let title: String
    /// The window's top-left screen position.
    let position: CGPoint
    /// The window's dimensions.
    let size: CGSize
    /// The Core Graphics window ID (stable for the lifetime of the window).
    let windowID: CGWindowID?
}

/// Retrieves all windows for the given application element.
/// Each window is returned as a `WindowInfo` with its index, title, position, and size.
func getWindows(appElement: AXUIElement) -> [WindowInfo] {
    var windowsRef: CFTypeRef?
    AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
    guard let windows = windowsRef as? [AXUIElement] else { return [] }

    var result: [WindowInfo] = []
    for (index, window) in windows.enumerated() {
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""

        var posRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        var position = CGPoint.zero
        if let posRef = posRef {
            // AXValue is a CFTypeRef subtype; the AX API guarantees this cast for position attributes
            AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        }

        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        var size = CGSize.zero
        if let sizeRef = sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }

        result.append(WindowInfo(element: window, id: index, title: title, position: position, size: size, windowID: getCGWindowID(window)))
    }
    return result
}

/// Moves a window to the specified screen coordinates.
func moveWindow(_ window: AXUIElement, x: CGFloat, y: CGFloat) {
    var point = CGPoint(x: x, y: y)
    if let value = AXValueCreate(.cgPoint, &point) {
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
}

/// Resizes a window to the specified width and height.
func resizeWindow(_ window: AXUIElement, width: CGFloat, height: CGFloat) {
    var size = CGSize(width: width, height: height)
    if let value = AXValueCreate(.cgSize, &size) {
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}

// MARK: - Window Resolution

enum WindowSelector {
    case byIndex(Int)
    case byTitle(String)
    case byWindowID(CGWindowID)
}

/// Parses a window selector from a string argument.
/// Supports `id=<windowID>` for CGWindowID or a plain integer for index.
func parseWindowSelector(_ arg: String) throws -> WindowSelector {
    if arg.hasPrefix("id=") {
        let idStr = String(arg.dropFirst(3))
        guard let id = UInt32(idStr) else {
            throw WindowToolError.invalidArgument(value: arg, label: "window ID")
        }
        return .byWindowID(CGWindowID(id))
    }
    return .byIndex(try parseInt(arg, label: "index"))
}

func requireApp(_ bundleId: String) throws -> AXUIElement {
    guard let app = getAppElement(bundleId: bundleId) else {
        throw WindowToolError.appNotFound(bundleId)
    }
    return app
}

func resolveWindow(bundleId: String, selector: WindowSelector) throws -> WindowInfo {
    let app = try requireApp(bundleId)
    let windows = getWindows(appElement: app)
    switch selector {
    case .byIndex(let index):
        guard windows.indices.contains(index) else {
            throw WindowToolError.windowIndexOutOfRange(index: index, count: windows.count)
        }
        return windows[index]
    case .byTitle(let pattern):
        guard let window = windows.first(where: { $0.title.contains(pattern) }) else {
            throw WindowToolError.noWindowMatchingTitle(pattern)
        }
        return window
    case .byWindowID(let windowID):
        guard let window = windows.first(where: { $0.windowID == windowID }) else {
            throw WindowToolError.noWindowMatchingID(windowID)
        }
        return window
    }
}

func resolveAllWindows(bundleId: String, selector: WindowSelector) throws -> [WindowInfo] {
    let app = try requireApp(bundleId)
    let windows = getWindows(appElement: app)
    switch selector {
    case .byIndex(let index):
        guard windows.indices.contains(index) else {
            throw WindowToolError.windowIndexOutOfRange(index: index, count: windows.count)
        }
        return [windows[index]]
    case .byTitle(let pattern):
        let matching = windows.filter { $0.title.contains(pattern) }
        guard !matching.isEmpty else {
            throw WindowToolError.noWindowMatchingTitle(pattern)
        }
        return matching
    case .byWindowID(let windowID):
        guard let window = windows.first(where: { $0.windowID == windowID }) else {
            throw WindowToolError.noWindowMatchingID(windowID)
        }
        return [window]
    }
}

// MARK: - Screen Helpers

/// Prints info for all connected displays.
/// Output columns: index, frame origin, frame size, visible origin, visible size, and flags ([main], [mouse]).
func screensCommand() {
    let mouseLocation = NSEvent.mouseLocation
    if config.jsonOutput {
        var items: [[String: Any]] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            items.append([
                "index": index,
                "frame_x": Int(frame.origin.x), "frame_y": Int(frame.origin.y),
                "frame_width": Int(frame.width), "frame_height": Int(frame.height),
                "visible_x": Int(visible.origin.x), "visible_y": Int(visible.origin.y),
                "visible_width": Int(visible.width), "visible_height": Int(visible.height),
                "main": screen == NSScreen.main,
                "mouse": frame.contains(mouseLocation)
            ])
        }
        printJSON(items)
    } else {
        print("INDEX\tFRAME_ORIGIN\tFRAME_SIZE\tVISIBLE_ORIGIN\tVISIBLE_SIZE\tFLAGS")
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            let isMain = (screen == NSScreen.main)
            let containsMouse = frame.contains(mouseLocation)
            var flags: [String] = []
            if isMain { flags.append("main") }
            if containsMouse { flags.append("mouse") }
            let flagStr = flags.isEmpty ? "" : "[\(flags.joined(separator: ","))]"
            print("\(index)\t\(Int(frame.origin.x)),\(Int(frame.origin.y))\t\(Int(frame.width))x\(Int(frame.height))\t\(Int(visible.origin.x)),\(Int(visible.origin.y))\t\(Int(visible.width))x\(Int(visible.height))\t\(flagStr)")
        }
    }
}

/// Prints the visible bounds of the screen containing the mouse cursor.
/// Output: tab-separated x, y (top-left origin), width, height of the usable area.
func printWindowInfo(_ w: WindowInfo, bundleId: String? = nil) {
    let minimized = axBool(w.element, kAXMinimizedAttribute as String)
    let fullscreen = axBool(w.element, "AXFullScreen")
    let focused = axBool(w.element, kAXFocusedAttribute as String)
    let main = axBool(w.element, kAXMainAttribute as String)
    let modal = axBool(w.element, "AXModal")
    let role = axString(w.element, kAXRoleAttribute as String)
    let subrole = axString(w.element, kAXSubroleAttribute as String)
    let document = axString(w.element, kAXDocumentAttribute as String)

    if config.jsonOutput {
        var dict: [String: Any] = [
            "index": w.id, "title": w.title,
            "x": Int(w.position.x), "y": Int(w.position.y),
            "width": Int(w.size.width), "height": Int(w.size.height),
            "minimized": minimized, "fullscreen": fullscreen,
            "focused": focused, "main": main, "modal": modal
        ]
        if let bundleId = bundleId { dict["bundle_id"] = bundleId }
        if let wid = w.windowID { dict["window_id"] = Int(wid) }
        if let role = role { dict["role"] = role }
        if let subrole = subrole { dict["subrole"] = subrole }
        if let document = document { dict["document"] = document }
        printJSON(dict)
    } else {
        if let bundleId = bundleId { print("bundle_id:\t\(bundleId)") }
        print("index:\t\(w.id)")
        if let wid = w.windowID { print("window_id:\t\(wid)") }
        print("title:\t\(w.title)")
        print("position:\t\(Int(w.position.x)),\(Int(w.position.y))")
        print("size:\t\(Int(w.size.width))x\(Int(w.size.height))")
        if let role = role { print("role:\t\(role)") }
        if let subrole = subrole { print("subrole:\t\(subrole)") }
        print("focused:\t\(focused)")
        print("main:\t\(main)")
        print("minimized:\t\(minimized)")
        print("fullscreen:\t\(fullscreen)")
        print("modal:\t\(modal)")
        if let document = document { print("document:\t\(document)") }
    }
}

/// Prints info about the frontmost application's primary window.
func activeWindowCommand() throws {
    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          let bundleId = frontApp.bundleIdentifier else {
        throw WindowToolError.appNotFound("(no frontmost application)")
    }
    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
    let windows = getWindows(appElement: appElement)

    guard let w = windows.first(where: { axBool($0.element, kAXMainAttribute as String) })
            ?? windows.first else {
        throw WindowToolError.windowIndexOutOfRange(index: 0, count: 0)
    }

    printWindowInfo(w, bundleId: bundleId)
}

func activeScreenCommand() {
    // Return the screen containing the mouse cursor (the "active" screen)
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    let frame = screen.frame
    let visible = screen.visibleFrame
    // Output: x,y width height visible_x,visible_y visible_width visible_height
    // NSScreen y-axis is bottom-up; convert visible frame to top-left origin for window positioning
    let topLeftY = frame.origin.y + frame.height - (visible.origin.y + visible.height)
    if config.jsonOutput {
        printJSON(["x": Int(frame.origin.x), "y": Int(topLeftY),
                   "width": Int(visible.width), "height": Int(visible.height)])
    } else {
        print("X\tY\tWIDTH\tHEIGHT")
        print("\(Int(frame.origin.x))\t\(Int(topLeftY))\t\(Int(visible.width))\t\(Int(visible.height))")
    }
}

// MARK: - Accessibility Check

/// Checks if the process has Accessibility API access and exits with a helpful message if not.
func checkAccessibility() throws {
    guard AXIsProcessTrusted() else {
        throw WindowToolError.accessibilityNotEnabled
    }
}

// MARK: - Commands

/// Lists all windows for the given application.
/// Output columns (tab-separated): index, window_id, position (x,y), size (WxH), title.
func listCommand(bundleId: String) throws {
    let app = try requireApp(bundleId)
    let windows = getWindows(appElement: app)
    if config.jsonOutput {
        let items = windows.map { w in
            var dict: [String: Any] = ["index": w.id, "x": Int(w.position.x), "y": Int(w.position.y),
             "width": Int(w.size.width), "height": Int(w.size.height), "title": w.title]
            if let wid = w.windowID { dict["window_id"] = Int(wid) }
            return dict
        }
        printJSON(items)
    } else {
        print("INDEX\tWID\tPOSITION\tSIZE\tTITLE")
        for w in windows {
            let wid = w.windowID.map { String($0) } ?? "?"
            print("\(w.id)\t\(wid)\t\(Int(w.position.x)),\(Int(w.position.y))\t\(Int(w.size.width))x\(Int(w.size.height))\t\(w.title)")
        }
    }
}

/// Moves (and optionally resizes) window(s).
func moveCommand(bundleId: String, selector: WindowSelector, x: CGFloat, y: CGFloat, width: CGFloat?, height: CGFloat?) throws {
    let windows = try resolveAllWindows(bundleId: bundleId, selector: selector)
    for window in windows {
        moveWindow(window.element, x: x, y: y)
        if let w = width, let h = height {
            resizeWindow(window.element, width: w, height: h)
        }
    }
    if case .byTitle(let pattern) = selector {
        print("Moved \(windows.count) window(s) matching '\(pattern)'")
    }
}

/// Lists all running applications that have at least one open window.
/// Output: one line per window, with application name, bundle identifier, and window title.
/// Sorted alphabetically by application name.
func listOpenWindowsCommand() {
    let apps = NSWorkspace.shared.runningApplications
    var entries: [(bundleId: String, name: String, title: String)] = []
    var seen = Set<String>()
    for app in apps {
        guard let bundleId = app.bundleIdentifier, !seen.contains(bundleId),
              app.activationPolicy == .regular else { continue }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement: appElement)
        if !windows.isEmpty {
            seen.insert(bundleId)
            let appName = app.localizedName ?? "Unknown"
            for w in windows {
                entries.append((bundleId: bundleId, name: appName, title: w.title))
            }
        }
    }
    entries.sort(by: { $0.name.lowercased() < $1.name.lowercased() })
    if config.jsonOutput {
        let items = entries.map { e in
            ["app": e.name, "bundle_id": e.bundleId, "title": e.title]
        }
        printJSON(items)
    } else {
        let maxName = max(entries.map { $0.name.count }.max() ?? 0, 4)
        let maxBundleId = max(entries.map { $0.bundleId.count }.max() ?? 0, 9)
        let headerName = "APP".padding(toLength: maxName, withPad: " ", startingAt: 0)
        let headerBundleId = "BUNDLE ID".padding(toLength: maxBundleId, withPad: " ", startingAt: 0)
        print("\(headerName)  \(headerBundleId)  WINDOW TITLE")
        for entry in entries {
            let paddedName = entry.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
            let paddedBundleId = entry.bundleId.padding(toLength: maxBundleId, withPad: " ", startingAt: 0)
            print("\(paddedName)  \(paddedBundleId)  \(entry.title)")
        }
    }
}

/// Brings a window to the front. Activates the application and raises the window.
func focusCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    runningApps.first?.activate()
    AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
}

/// Shakes a window horizontally to draw attention, then restores its position.
func shakeCommand(bundleId: String, selector: WindowSelector, offset: Int, count: Int, delay: Double) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let originalX = window.position.x
    let originalY = window.position.y

    for _ in 0..<count {
        moveWindow(window.element, x: originalX + CGFloat(offset), y: originalY)
        Thread.sleep(forTimeInterval: delay)
        moveWindow(window.element, x: originalX - CGFloat(offset), y: originalY)
        Thread.sleep(forTimeInterval: delay)
    }
    moveWindow(window.element, x: originalX, y: originalY)
}

/// Flashes a colored overlay on a window as a visual notification.
func flashCommand(bundleId: String, selector: WindowSelector, color: NSColor, count: Int) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)

    let mainScreenHeight = NSScreen.screens[0].frame.height
    let flippedY = mainScreenHeight - window.position.y - window.size.height

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let overlay = NSWindow(
        contentRect: NSRect(x: window.position.x, y: flippedY,
                            width: window.size.width, height: window.size.height),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    overlay.backgroundColor = color.withAlphaComponent(0.4)
    overlay.isOpaque = false
    overlay.level = .floating
    overlay.ignoresMouseEvents = true
    overlay.hasShadow = false

    var remaining = count

    func doFlash() {
        overlay.alphaValue = 1.0
        overlay.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            overlay.animator().alphaValue = 0.0
        }, completionHandler: {
            remaining -= 1
            if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    doFlash()
                }
            } else {
                overlay.close()
                app.stop(nil)
                let event = NSEvent.otherEvent(with: .applicationDefined,
                    location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
                app.postEvent(event, atStart: true)
            }
        })
    }

    doFlash()
    app.run()
}

// MARK: - Highlight Overlay

class HighlightView: NSView {
    var borderColor: NSColor = .red
    var borderWidth: CGFloat = 4

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        path.lineWidth = borderWidth

        let shadow = NSShadow()
        shadow.shadowColor = borderColor.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 15
        shadow.shadowOffset = .zero
        shadow.set()

        borderColor.setStroke()
        path.stroke()
    }
}

func highlightCommand(bundleId: String, selector: WindowSelector, color: NSColor, duration: Double) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)

    let mainScreenHeight = NSScreen.screens[0].frame.height
    let cocoaY = mainScreenHeight - window.position.y - window.size.height
    let overlayFrame = NSRect(x: window.position.x, y: cocoaY,
                              width: window.size.width, height: window.size.height)

    let overlay = NSWindow(contentRect: overlayFrame,
                           styleMask: .borderless,
                           backing: .buffered,
                           defer: false)
    overlay.isOpaque = false
    overlay.backgroundColor = .clear
    overlay.level = .floating
    overlay.ignoresMouseEvents = true
    overlay.hasShadow = false

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let view = HighlightView(frame: NSRect(origin: .zero, size: overlayFrame.size))
    view.borderColor = color
    overlay.contentView = view
    overlay.orderFrontRegardless()

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        overlay.close()
        app.stop(nil)
        // app.stop() doesn't break out of run() immediately; post a dummy event to wake the run loop
        let dummyEvent = NSEvent.otherEvent(with: .applicationDefined,
                                            location: .zero,
                                            modifierFlags: [],
                                            timestamp: 0,
                                            windowNumber: 0,
                                            context: nil,
                                            subtype: 0,
                                            data1: 0,
                                            data2: 0)!
        app.postEvent(dummyEvent, atStart: true)
    }
    app.run()
}

// MARK: - Dim Overlay

let dimPIDFile = "/tmp/window-tool-dim.pid"

func parseDimFlags(_ args: [String]) throws -> (opacity: Double, duration: Double) {
    var opacity: Double = 0.5
    var duration: Double = 0
    if let idx = args.firstIndex(of: "--opacity") {
        guard idx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--opacity", label: "flag (requires a value)")
        }
        opacity = try parseDouble(args[idx + 1], label: "opacity")
    }
    if let idx = args.firstIndex(of: "--duration") {
        guard idx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--duration", label: "flag (requires a value)")
        }
        duration = try parseDouble(args[idx + 1], label: "duration")
    }
    return (opacity, duration)
}

class DimOverlayView: NSView {
    var cutoutRect: NSRect? = nil
    var dimColor: NSColor = NSColor.black.withAlphaComponent(0.5)

    override func draw(_ dirtyRect: NSRect) {
        dimColor.setFill()
        bounds.fill()
        if let cutout = cutoutRect {
            NSColor.clear.setFill()
            cutout.fill(using: .copy)
        }
    }
}

func killExistingDim() {
    guard FileManager.default.fileExists(atPath: dimPIDFile),
          let pidStr = try? String(contentsOfFile: dimPIDFile, encoding: .utf8),
          let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return
    }
    kill(pid, SIGTERM)
    try? FileManager.default.removeItem(atPath: dimPIDFile)
}

func dimCommand(bundleId: String, selector: WindowSelector, opacity: Double, duration: Double) throws {
    guard opacity >= 0.0 && opacity <= 1.0 else {
        throw WindowToolError.invalidArgument(value: "\(opacity)", label: "opacity (must be between 0.0 and 1.0)")
    }

    let window = try resolveWindow(bundleId: bundleId, selector: selector)

    killExistingDim()

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let mainScreenHeight = NSScreen.screens[0].frame.height
    let targetCocoaY = mainScreenHeight - window.position.y - window.size.height
    let targetRect = NSRect(x: window.position.x, y: targetCocoaY,
                            width: window.size.width, height: window.size.height)

    var overlays: [NSWindow] = []

    for screen in NSScreen.screens {
        let frame = screen.frame
        let overlay = NSWindow(contentRect: frame,
                               styleMask: .borderless,
                               backing: .buffered,
                               defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.level = .floating
        overlay.ignoresMouseEvents = true
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let view = DimOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        view.dimColor = NSColor.black.withAlphaComponent(opacity)

        if frame.intersects(targetRect) {
            let localRect = NSRect(
                x: targetRect.origin.x - frame.origin.x,
                y: targetRect.origin.y - frame.origin.y,
                width: targetRect.width,
                height: targetRect.height
            )
            view.cutoutRect = localRect
        }

        overlay.contentView = view
        overlay.orderFrontRegardless()
        overlays.append(overlay)
    }

    try "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: dimPIDFile, atomically: true, encoding: .utf8)

    let cleanupPID: @convention(c) (Int32) -> Void = { _ in
        try? FileManager.default.removeItem(atPath: dimPIDFile)
        exit(0)
    }
    signal(SIGTERM, cleanupPID)
    signal(SIGINT, cleanupPID)

    if duration > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            for overlay in overlays { overlay.close() }
            try? FileManager.default.removeItem(atPath: dimPIDFile)
            app.stop(nil)
            let dummyEvent = NSEvent.otherEvent(with: .applicationDefined,
                                                location: .zero, modifierFlags: [],
                                                timestamp: 0, windowNumber: 0,
                                                context: nil, subtype: 0,
                                                data1: 0, data2: 0)!
            app.postEvent(dummyEvent, atStart: true)
        }
    }

    app.run()
}

func undimCommand() throws {
    guard FileManager.default.fileExists(atPath: dimPIDFile),
          let pidStr = try? String(contentsOfFile: dimPIDFile, encoding: .utf8),
          let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw WindowToolError.invalidArgument(value: "none", label: "active dim overlay (run 'dim' first)")
    }
    let result = kill(pid, SIGTERM)
    try? FileManager.default.removeItem(atPath: dimPIDFile)
    if result != 0 {
        throw WindowToolError.invalidArgument(value: "\(pid)", label: "dim process (process not found)")
    }
}

// MARK: - Border Overlay

let borderPidDir = "/tmp/window-tool-borders"

class BorderView: NSView {
    var borderColor: NSColor = .blue
    var borderWidth: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        path.lineWidth = borderWidth
        borderColor.setStroke()
        path.stroke()
    }
}

func borderCommand(bundleId: String, selector: WindowSelector, color: NSColor, width: CGFloat) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    guard let windowID = window.windowID else {
        fputs("Error: Could not determine window ID\n", stderr)
        exit(1)
    }

    let appBundleDir = "\(borderPidDir)/\(bundleId)"
    try FileManager.default.createDirectory(atPath: appBundleDir, withIntermediateDirectories: true)
    let pidFile = "\(appBundleDir)/\(windowID).pid"

    if let existingPid = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = Int32(existingPid) {
        kill(pid, SIGTERM)
        usleep(200_000)
    }

    try "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidFile, atomically: true, encoding: .utf8)

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let mainScreenHeight = NSScreen.screens[0].frame.height
    let cocoaY = mainScreenHeight - window.position.y - window.size.height
    let overlayFrame = NSRect(x: window.position.x, y: cocoaY,
                              width: window.size.width, height: window.size.height)

    let overlay = NSWindow(contentRect: overlayFrame,
                           styleMask: .borderless,
                           backing: .buffered,
                           defer: false)
    overlay.isOpaque = false
    overlay.backgroundColor = .clear
    overlay.level = .floating
    overlay.ignoresMouseEvents = true
    overlay.hasShadow = false

    let view = BorderView(frame: NSRect(origin: .zero, size: overlayFrame.size))
    view.borderColor = color
    view.borderWidth = width
    overlay.contentView = view
    overlay.orderFrontRegardless()

    func cleanupAndExit() {
        overlay.close()
        try? FileManager.default.removeItem(atPath: pidFile)
        app.stop(nil)
        let event = NSEvent.otherEvent(with: .applicationDefined,
            location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        app.postEvent(event, atStart: true)
    }

    signal(SIGTERM, SIG_IGN)
    let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termSource.setEventHandler { cleanupAndExit() }
    termSource.resume()

    signal(SIGINT, SIG_IGN)
    let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    intSource.setEventHandler { cleanupAndExit() }
    intSource.resume()

    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
        guard let appElement = getAppElement(bundleId: bundleId) else {
            timer.invalidate()
            cleanupAndExit()
            return
        }
        let windows = getWindows(appElement: appElement)
        guard let w = windows.first(where: { $0.windowID == windowID }) else {
            timer.invalidate()
            cleanupAndExit()
            return
        }

        let screenHeight = NSScreen.screens[0].frame.height
        let newCocoaY = screenHeight - w.position.y - w.size.height
        let newFrame = NSRect(x: w.position.x, y: newCocoaY,
                              width: w.size.width, height: w.size.height)
        if overlay.frame != newFrame {
            overlay.setFrame(newFrame, display: false)
            view.frame = NSRect(origin: .zero, size: newFrame.size)
            view.needsDisplay = true
        }
    }

    app.run()
    try? FileManager.default.removeItem(atPath: pidFile)
}

func unborderCommand(bundleId: String, selector: WindowSelector? = nil) {
    let appDir = "\(borderPidDir)/\(bundleId)"

    if let selector = selector {
        guard let window = try? resolveWindow(bundleId: bundleId, selector: selector),
              let windowID = window.windowID else {
            return
        }
        let pidFile = "\(appDir)/\(windowID).pid"
        if let content = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(content) {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: pidFile)
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: appDir), remaining.isEmpty {
            try? FileManager.default.removeItem(atPath: appDir)
        }
        return
    }

    guard let files = try? FileManager.default.contentsOfDirectory(atPath: appDir) else {
        return
    }
    for file in files where file.hasSuffix(".pid") {
        let pidFile = "\(appDir)/\(file)"
        if let content = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(content) {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: pidFile)
    }
    try? FileManager.default.removeItem(atPath: appDir)
}

func unborderAllCommand() {
    guard let bundleDirs = try? FileManager.default.contentsOfDirectory(atPath: borderPidDir) else {
        return
    }
    for bundleDir in bundleDirs {
        unborderCommand(bundleId: bundleDir)
    }
}

/// Resizes window(s) without changing position.
func resizeCommand(bundleId: String, selector: WindowSelector, width: CGFloat, height: CGFloat) throws {
    let windows = try resolveAllWindows(bundleId: bundleId, selector: selector)
    for window in windows {
        resizeWindow(window.element, width: width, height: height)
    }
    if case .byTitle(let pattern) = selector {
        print("Resized \(windows.count) window(s) matching '\(pattern)'")
    }
}

/// Returns the visible frame of the screen containing the given window, converted to top-left origin.
func screenBoundsForWindow(_ window: WindowInfo) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    let windowCenter = NSPoint(x: window.position.x + window.size.width / 2,
                                y: window.position.y + window.size.height / 2)
    // NSScreen uses bottom-left origin; convert window center for lookup
    let mainHeight = NSScreen.screens[0].frame.height
    let flippedCenter = NSPoint(x: windowCenter.x, y: mainHeight - windowCenter.y)
    let screen = NSScreen.screens.first { $0.frame.contains(flippedCenter) } ?? NSScreen.main ?? NSScreen.screens[0]
    let frame = screen.frame
    let visible = screen.visibleFrame
    let topLeftY = frame.origin.y + frame.height - (visible.origin.y + visible.height)
    return (x: visible.origin.x, y: topLeftY, width: visible.width, height: visible.height)
}

enum SnapPosition: String, CaseIterable {
    case left, right, top, bottom
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case center, maximize

    static var allNames: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}

/// Snaps a window to a named screen region.
func snapCommand(bundleId: String, selector: WindowSelector, position: SnapPosition) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let bounds = screenBoundsForWindow(window)
    let halfW = bounds.width / 2
    let halfH = bounds.height / 2

    switch position {
    case .left:
        moveWindow(window.element, x: bounds.x, y: bounds.y)
        resizeWindow(window.element, width: halfW, height: bounds.height)
    case .right:
        moveWindow(window.element, x: bounds.x + halfW, y: bounds.y)
        resizeWindow(window.element, width: halfW, height: bounds.height)
    case .top:
        moveWindow(window.element, x: bounds.x, y: bounds.y)
        resizeWindow(window.element, width: bounds.width, height: halfH)
    case .bottom:
        moveWindow(window.element, x: bounds.x, y: bounds.y + halfH)
        resizeWindow(window.element, width: bounds.width, height: halfH)
    case .topLeft:
        moveWindow(window.element, x: bounds.x, y: bounds.y)
        resizeWindow(window.element, width: halfW, height: halfH)
    case .topRight:
        moveWindow(window.element, x: bounds.x + halfW, y: bounds.y)
        resizeWindow(window.element, width: halfW, height: halfH)
    case .bottomLeft:
        moveWindow(window.element, x: bounds.x, y: bounds.y + halfH)
        resizeWindow(window.element, width: halfW, height: halfH)
    case .bottomRight:
        moveWindow(window.element, x: bounds.x + halfW, y: bounds.y + halfH)
        resizeWindow(window.element, width: halfW, height: halfH)
    case .center:
        let w = window.size.width
        let h = window.size.height
        moveWindow(window.element, x: bounds.x + (bounds.width - w) / 2, y: bounds.y + (bounds.height - h) / 2)
    case .maximize:
        moveWindow(window.element, x: bounds.x, y: bounds.y)
        resizeWindow(window.element, width: bounds.width, height: bounds.height)
    }
}

/// Maximizes window(s) to fill the visible screen area.
func maximizeCommand(bundleId: String, selector: WindowSelector) throws {
    let windows = try resolveAllWindows(bundleId: bundleId, selector: selector)
    for window in windows {
        let bounds = screenBoundsForWindow(window)
        moveWindow(window.element, x: bounds.x, y: bounds.y)
        resizeWindow(window.element, width: bounds.width, height: bounds.height)
    }
    if case .byTitle(let pattern) = selector {
        print("Maximized \(windows.count) window(s) matching '\(pattern)'")
    }
}

/// Enters macOS fullscreen mode for a window.
func fullscreenCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, true as CFTypeRef)
}

/// Exits macOS fullscreen mode for a window.
func unfullscreenCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, false as CFTypeRef)
}

/// Moves a window to a different screen, placing it at the top-left of the visible area.
func moveToScreenCommand(bundleId: String, selector: WindowSelector, screenIndex: Int) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let screens = NSScreen.screens
    guard screens.indices.contains(screenIndex) else {
        throw WindowToolError.screenIndexOutOfRange(index: screenIndex, count: screens.count)
    }
    let targetScreen = screens[screenIndex]
    let frame = targetScreen.frame
    let visible = targetScreen.visibleFrame
    let topLeftY = frame.origin.y + frame.height - (visible.origin.y + visible.height)
    moveWindow(window.element, x: visible.origin.x, y: topLeftY)
}

/// Minimizes a window.
func minimizeCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, true as CFTypeRef)
}

/// Restores (unminimizes) all minimized windows for the given application.
func restoreCommand(bundleId: String) throws {
    let app = try requireApp(bundleId)
    var windowsRef: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
    guard let windows = windowsRef as? [AXUIElement] else { return }
    var restored = 0
    for window in windows {
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
        if let minimized = minimizedRef as? Bool, minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            restored += 1
        }
    }
    print("Restored \(restored) window(s)")
}

/// Reads an AX boolean attribute, returning false if unavailable.
func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
    return (ref as? Bool) ?? false
}

/// Reads an AX string attribute, returning nil if unavailable.
func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
    return ref as? String
}

/// Prints detailed info for a single window.
func infoCommand(bundleId: String, selector: WindowSelector) throws {
    let w = try resolveWindow(bundleId: bundleId, selector: selector)
    printWindowInfo(w)
}

// MARK: - Preview Command

func captureWindowImage(windowID: CGWindowID) throws -> CGImage {
    NSApplication.shared.setActivationPolicy(.accessory)
    let semaphore = DispatchSemaphore(value: 0)
    var capturedImage: CGImage?
    var captureError: (any Error)?

    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                captureError = WindowToolError.noWindowMatchingID(windowID)
                semaphore.signal()
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.captureResolution = .best
            config.showsCursor = false
            capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            captureError = error
        }
        semaphore.signal()
    }

    semaphore.wait()

    if let error = captureError { throw error }
    guard let image = capturedImage else {
        fputs("Error: Failed to capture window image\n", stderr)
        exit(1)
    }
    return image
}

func parsePreviewFlags(_ args: [String]) throws -> String? {
    guard let outIdx = args.firstIndex(of: "--output") else { return nil }
    guard outIdx + 1 < args.count else {
        throw WindowToolError.invalidArgument(value: "--output", label: "flag (requires a file path)")
    }
    return args[outIdx + 1]
}

func previewCommand(bundleId: String, selector: WindowSelector, outputPath: String?) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    guard let windowID = window.windowID else {
        fputs("Error: Cannot capture window — no window ID available\n", stderr)
        exit(1)
    }

    let image = try captureWindowImage(windowID: windowID)

    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Error: Failed to encode PNG\n", stderr)
        exit(1)
    }

    let resolvedPath: String
    if let path = outputPath {
        resolvedPath = (path as NSString).expandingTildeInPath
    } else {
        resolvedPath = "/tmp/window-tool-preview-\(windowID).png"
    }
    let url = URL(fileURLWithPath: resolvedPath)
    try pngData.write(to: url)

    if config.jsonOutput {
        printJSON([
            "path": url.path,
            "window_id": Int(windowID),
            "width": image.width,
            "height": image.height
        ])
    } else {
        print(url.path)
    }
}

// MARK: - Record Command

func parseRecordFlags(_ args: [String]) throws -> (output: String, fps: Int, duration: Double?, countdown: Bool, border: Bool) {
    guard let outIdx = args.firstIndex(of: "--output") else {
        throw WindowToolError.invalidArgument(value: "--output", label: "flag (required, specify an output file path)")
    }
    guard outIdx + 1 < args.count else {
        throw WindowToolError.invalidArgument(value: "--output", label: "flag (requires a file path)")
    }
    let output = args[outIdx + 1]

    var fps = 30
    if let fpsIdx = args.firstIndex(of: "--fps") {
        guard fpsIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--fps", label: "flag (requires a value)")
        }
        fps = try parseInt(args[fpsIdx + 1], label: "fps")
    }

    var duration: Double? = nil
    if let durIdx = args.firstIndex(of: "--duration") {
        guard durIdx + 1 < args.count else {
            throw WindowToolError.invalidArgument(value: "--duration", label: "flag (requires a value)")
        }
        duration = try parseDouble(args[durIdx + 1], label: "duration")
    }

    let countdown = !args.contains("--no-countdown")
    let border = !args.contains("--no-border")

    return (output, fps, duration, countdown, border)
}

class RecordingDelegate: NSObject, SCStreamOutput {
    let assetWriter: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let fps: Int
    var startTime: CFAbsoluteTime?
    var lastPixelBuffer: CVPixelBuffer?
    var frameTimer: DispatchSourceTimer?
    private let lock = NSLock()

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, fps: Int) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.fps = fps
    }

    func startFrameTimer() {
        startTime = CFAbsoluteTimeGetCurrent()
        assetWriter.startSession(atSourceTime: .zero)

        let interval = 1.0 / Double(fps)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.window-tool.frame-timer"))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.writeFrame()
        }
        timer.resume()
        frameTimer = timer
    }

    func stopFrameTimer() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func writeFrame() {
        lock.lock()
        let pb = lastPixelBuffer
        lock.unlock()

        guard let pixelBuffer = pb, let start = startTime else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let time = CMTime(seconds: elapsed, preferredTimescale: CMTimeScale(fps * 100))
        if videoInput.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue),
              status == .complete else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lock.lock()
        lastPixelBuffer = pixelBuffer
        lock.unlock()
    }
}

func makeRecordingBorderOverlay(frame: NSRect, color: NSColor, width: CGFloat) -> NSWindow {
    let overlay = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    overlay.isOpaque = false
    overlay.backgroundColor = .clear
    overlay.level = .floating
    overlay.ignoresMouseEvents = true
    overlay.hasShadow = false
    let view = BorderView(frame: NSRect(origin: .zero, size: frame.size))
    view.borderColor = color
    view.borderWidth = width
    overlay.contentView = view
    overlay.orderFrontRegardless()
    return overlay
}

func makeCountdownOverlay(frame: NSRect) -> NSWindow {
    let overlaySize = NSSize(width: 120, height: 120)
    let overlayX = frame.origin.x + (frame.width - overlaySize.width) / 2
    let overlayY = frame.origin.y + (frame.height - overlaySize.height) / 2
    let overlay = NSWindow(
        contentRect: NSRect(origin: NSPoint(x: overlayX, y: overlayY), size: overlaySize),
        styleMask: .borderless, backing: .buffered, defer: false
    )
    overlay.isOpaque = false
    overlay.backgroundColor = NSColor.black.withAlphaComponent(0.7)
    overlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    overlay.ignoresMouseEvents = true
    overlay.hasShadow = false

    let label = NSTextField(labelWithString: "3")
    label.font = NSFont.systemFont(ofSize: 64, weight: .bold)
    label.textColor = .white
    label.alignment = .center
    label.frame = NSRect(origin: .zero, size: overlaySize)
    overlay.contentView = label
    overlay.orderFrontRegardless()
    return overlay
}

func startRecording(windowID: CGWindowID, output: String, fps: Int, duration: Double?, borderOverlay: NSWindow?) {
    let semaphore = DispatchSemaphore(value: 0)
    var setupError: (any Error)?

    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                setupError = WindowToolError.noWindowMatchingID(windowID)
                semaphore.signal()
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let streamConfig = SCStreamConfiguration()
            streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
            streamConfig.showsCursor = true
            streamConfig.captureResolution = .best
            streamConfig.queueDepth = 3

            let contentRect = filter.contentRect
            let pointPixelScale = filter.pointPixelScale
            let width = Int(contentRect.width * CGFloat(pointPixelScale))
            let height = Int(contentRect.height * CGFloat(pointPixelScale))
            streamConfig.width = width
            streamConfig.height = height

            let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
            try? FileManager.default.removeItem(at: outputURL)
            let fileType: AVFileType = outputURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
            let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            assetWriter.add(videoInput)

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)

            guard assetWriter.startWriting() else {
                fputs("Error: Failed to start writing: \(assetWriter.error?.localizedDescription ?? "unknown")\n", stderr)
                exit(1)
            }

            let delegate = RecordingDelegate(assetWriter: assetWriter, videoInput: videoInput, adaptor: adaptor, fps: fps)
            let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
            try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.window-tool.record"))

            try await stream.startCapture()
            delegate.startFrameTimer()

            fputs("Recording window \(windowID) to \(outputURL.path) (\(width)x\(height) @ \(fps)fps)\n", stderr)
            fputs("Press Ctrl-C to stop recording\n", stderr)

            var stopping = false
            func stopRecording() {
                guard !stopping else { return }
                stopping = true
                delegate.stopFrameTimer()
                if let overlay = borderOverlay {
                    DispatchQueue.main.async { overlay.orderOut(nil) }
                }
                Task {
                    try? await stream.stopCapture()
                    videoInput.markAsFinished()
                    await assetWriter.finishWriting()
                    fputs("Recording saved to \(outputURL.path)\n", stderr)
                    if config.jsonOutput {
                        printJSON(["path": outputURL.path, "window_id": Int(windowID), "width": width, "height": height])
                    } else {
                        print(outputURL.path)
                    }
                    exit(0)
                }
            }

            signal(SIGINT, SIG_IGN)
            let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            intSource.setEventHandler { stopRecording() }
            intSource.resume()

            signal(SIGTERM, SIG_IGN)
            let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            termSource.setEventHandler { stopRecording() }
            termSource.resume()

            if let duration = duration {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    stopRecording()
                }
            }

        } catch let error as NSError where error.domain == "com.apple.ScreenCaptureKit.ErrorDomain" {
            fputs("Error: Screen Recording permission is not granted.\nGrant access in System Settings > Privacy & Security > Screen Recording.\n", stderr)
            exit(1)
        } catch {
            setupError = error
            semaphore.signal()
        }
    }

    DispatchQueue.global().async {
        semaphore.wait()
        if let error = setupError {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

func recordCommand(bundleId: String, selector: WindowSelector, output: String, fps: Int, duration: Double?, countdown: Bool, border: Bool) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    guard let windowID = window.windowID else {
        fputs("Error: Cannot record window — no window ID available\n", stderr)
        exit(1)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let mainScreenHeight = NSScreen.screens[0].frame.height
    let cocoaY = mainScreenHeight - window.position.y - window.size.height
    let windowFrame = NSRect(x: window.position.x, y: cocoaY,
                             width: window.size.width, height: window.size.height)

    var borderOverlay: NSWindow? = nil

    if countdown {
        borderOverlay = border ? makeRecordingBorderOverlay(frame: windowFrame, color: .red, width: 4) : nil
        let countdownOverlay = makeCountdownOverlay(frame: windowFrame)

        var remaining = 3
        fputs("Recording starts in 3...\n", stderr)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            remaining -= 1
            if remaining > 0 {
                fputs("\(remaining)...\n", stderr)
                (countdownOverlay.contentView as? NSTextField)?.stringValue = "\(remaining)"
            } else {
                timer.invalidate()
                countdownOverlay.orderOut(nil)
                if let view = borderOverlay?.contentView as? BorderView {
                    view.borderColor = .green
                    view.needsDisplay = true
                }
                startRecording(windowID: windowID, output: output, fps: fps, duration: duration, borderOverlay: borderOverlay)
            }
        }
    } else {
        borderOverlay = border ? makeRecordingBorderOverlay(frame: windowFrame, color: .green, width: 4) : nil
        startRecording(windowID: windowID, output: output, fps: fps, duration: duration, borderOverlay: borderOverlay)
    }

    app.run()
}

// MARK: - Layout Types

struct WindowSnapshot: Codable {
    let index: Int
    let title: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct WindowLayout: Codable {
    let bundleId: String
    let windows: [WindowSnapshot]

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case windows
    }
}

/// Saves the current window layout for an application to a JSON file.
func saveLayoutCommand(bundleId: String, filePath: String) throws {
    let app = try requireApp(bundleId)
    let windows = getWindows(appElement: app)
    let snapshots = windows.map { w in
        WindowSnapshot(index: w.id, title: w.title,
                       x: Int(w.position.x), y: Int(w.position.y),
                       width: Int(w.size.width), height: Int(w.size.height))
    }
    let layout = WindowLayout(bundleId: bundleId, windows: snapshots)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(layout)
    try data.write(to: URL(fileURLWithPath: filePath))
    print("Saved \(windows.count) window(s) to \(filePath)")
}

/// Restores window positions and sizes from a previously saved layout file.
/// Matches windows by title. Windows that can't be matched are skipped.
func restoreLayoutCommand(filePath: String) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let layout = try JSONDecoder().decode(WindowLayout.self, from: data)
    let app = try requireApp(layout.bundleId)
    let currentWindows = getWindows(appElement: app)
    var restored = 0
    for saved in layout.windows {
        if let match = currentWindows.first(where: { $0.title == saved.title }) {
            moveWindow(match.element, x: CGFloat(saved.x), y: CGFloat(saved.y))
            resizeWindow(match.element, width: CGFloat(saved.width), height: CGFloat(saved.height))
            restored += 1
        }
    }
    print("Restored \(restored)/\(layout.windows.count) window(s) for \(layout.bundleId)")
}

/// Cascades all windows for an application, offsetting each by a fixed amount.
func stackCommand(bundleId: String, offsetStep: Int) throws {
    let app = try requireApp(bundleId)
    let windows = getWindows(appElement: app)
    if windows.isEmpty { return }
    let s = screenBoundsForWindow(windows[0])
    for (i, w) in windows.enumerated() {
        let offset = CGFloat(i * offsetStep)
        moveWindow(w.element, x: s.x + offset, y: s.y + offset)
    }
    print("Stacked \(windows.count) window(s)")
}

/// Watches for window changes and prints updates.
func watchCommand(bundleId: String, interval: Double) throws {
    let app = try requireApp(bundleId)

    struct WindowState: Equatable {
        let title: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    func snapshot() -> [WindowState] {
        let windows = getWindows(appElement: app)
        return windows.map { WindowState(title: $0.title, x: Int($0.position.x), y: Int($0.position.y),
                                          width: Int($0.size.width), height: Int($0.size.height)) }
    }

    func printState(_ windows: [WindowState]) {
        if config.jsonOutput {
            let items = windows.enumerated().map { (i, w) in
                ["index": i, "x": w.x, "y": w.y,
                 "width": w.width, "height": w.height, "title": w.title] as [String: Any]
            }
            printJSON(items)
        } else {
            for (i, w) in windows.enumerated() {
                print("\(i)\t\(w.x),\(w.y)\t\(w.width)x\(w.height)\t\(w.title)")
            }
        }
    }

    if !config.jsonOutput {
        print("INDEX\tPOSITION\tSIZE\tTITLE")
    }
    var previous = snapshot()
    printState(previous)
    fflush(stdout)

    signal(SIGINT) { _ in exit(0) }

    while true {
        Thread.sleep(forTimeInterval: interval)
        let current = snapshot()
        if current != previous {
            if !config.jsonOutput { print("---") }
            printState(current)
            fflush(stdout)
            previous = current
        }
    }
}

/// Arranges windows side-by-side in non-overlapping columns and brings them to the front.
func columnizeCommand(bundleId: String, selectors: [WindowSelector], gap: Int) throws {
    var selected: [WindowInfo] = []
    for selector in selectors {
        selected.append(try resolveWindow(bundleId: bundleId, selector: selector))
    }

    let bounds = screenBoundsForWindow(selected[0])
    let count = CGFloat(selected.count)
    let totalGap = CGFloat(gap) * (count - 1)
    let colWidth = (bounds.width - totalGap) / count

    let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    runningApps.first?.activate()

    for (i, window) in selected.enumerated() {
        let x = bounds.x + CGFloat(i) * (colWidth + CGFloat(gap))
        moveWindow(window.element, x: x, y: bounds.y)
        resizeWindow(window.element, width: colWidth, height: bounds.height)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }
    print("Arranged \(selected.count) window(s) in columns")
}

/// Prints the number of windows for the given application. Prints "0" if the app is not found.
func countCommand(bundleId: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        if config.jsonOutput { printJSON(["count": 0]) } else { print("0") }
        return  // count returns 0 for unknown apps rather than erroring
    }
    let windows = getWindows(appElement: app)
    if config.jsonOutput { printJSON(["count": windows.count]) } else { print("\(windows.count)") }
}

// MARK: - Main

/// Prints the CLI usage/help text.
func usage() {
    let help = """
    Usage: window-tool [--app <name-or-id>] <command> [args...]

    Commands:
      active-screen                            Print active screen bounds (x, y, width, height)
      active-window                            Print info about the frontmost app's primary window
      columnize <w> <w> [<w>...] [--gap N]     Arrange windows side-by-side in columns
      count                                    Print number of windows
      dim <window> [--opacity 0.5] [--duration 0]  Dim everything except a window
      dim-by-title <pattern> [--opacity 0.5] [--duration 0]  Dim by title match
      flash <window> [--color green] [--count 1]  Flash a colored overlay on a window
      flash-by-title <pattern> [--color green] [--count 1]  Flash overlay by title match
      focus <window>                           Bring window to front
      focus-by-title <pattern>                 Bring window to front by title match
      fullscreen <window>                      Enter macOS fullscreen mode
      fullscreen-by-title <pattern>            Enter fullscreen by title match
      border <window> [--color blue] [--width 3]    Add a persistent border that tracks a window
      border-by-title <pattern> [--color blue] [--width 3]  Persistent border by title match
      highlight <window> [--color C] [--duration S]  Briefly highlight a window (auto-dismisses)
      highlight-by-title <pattern> [--color C] [--duration S]  Brief highlight by title match
      info <window>                            Show detailed info for a window
      list                                     List all windows with index, window ID, position, size, and title
      list-open-windows                        List apps with open windows
      maximize <window>                        Maximize window to fill screen
      maximize-by-title <pattern>              Maximize windows matching title
      minimize <window>                        Minimize a window
      minimize-by-title <pattern>              Minimize a window by title match
      move <window> <x> <y> [<w> <h>]          Move/resize window
      move-by-title <pattern> <x> <y> [<w> <h>]  Move/resize windows matching title
      move-to-screen <window> <screen>         Move window to a different display
      move-to-screen-by-title <pattern> <screen>  Move window to display by title
      preview <window> [--output <path>]       Capture a window screenshot as PNG
      preview-by-title <pattern> [--output <path>]  Capture window screenshot by title
      record <window> --output <path> [options]  Record video of a window
      record-by-title <pattern> --output <path> [options]  Record video by title
        Record options: [--fps 30] [--duration <seconds>] [--no-countdown] [--no-border]
      resize <window> <width> <height>         Resize window
      resize-by-title <pattern> <width> <height>  Resize windows matching title
      restore                                  Restore all minimized windows
      restore-layout <file>                    Restore window layout from a JSON file
      save-layout <file>                       Save window layout to a JSON file
      screens                                  List all displays with bounds
      shake <window> [offset] [count] [delay]  Shake a window
      shake-by-title <pattern> [offset] [count] [delay]  Shake a window by title match
      snap <window> <position>                 Snap window to screen region
      snap-by-title <pattern> <position>       Snap window to screen region by title
      stack [offset]                           Cascade windows with offset (default: 30)
      unborder [<window>]                          Remove borders for target app (or one window)
      unborder-by-title <pattern>                Remove border by title match
      unborder-all                               Remove all active borders
      undim                                    Remove active dim overlay
      unfullscreen <window>                     Exit macOS fullscreen mode
      unfullscreen-by-title <pattern>          Exit fullscreen by title match
      watch [interval]                         Watch for window changes (default: 1.0s)

    Window selectors:
      <window> can be an index (0, 1, 2...) or id=<window_id> (e.g., id=1341)
      Use 'list' to see available indices and window IDs

    Snap positions:
      left, right, top, bottom, top-left, top-right,
      bottom-left, bottom-right, center, maximize

    Colors:
      red, green, blue, yellow, orange, purple, white, cyan, magenta, random

    Options:
      --app <name-or-id>  Target application by name or bundle ID (default: com.googlecode.iterm2)
      --json              Output in JSON format
      --version, -v       Print version and exit

    Examples:
      window-tool list
      window-tool --app Safari list
      window-tool --app iTerm columnize 0 1 2
      window-tool move 0 100 50 1200 900
      window-tool focus id=1341
      window-tool move-by-title "my-notes" 0 0 1400 1000
    """
    print(help)
}

var args = Array(CommandLine.arguments.dropFirst())

// Parse --json flag
if let jsonIdx = args.firstIndex(of: "--json") {
    config.jsonOutput = true
    args.remove(at: jsonIdx)
}

// Parse --app flag
if let appIdx = args.firstIndex(of: "--app") {
    guard appIdx + 1 < args.count else {
        fputs("Error: --app requires an app name or bundle identifier\n", stderr)
        exit(1)
    }
    config.bundleId = args[appIdx + 1]
    args.removeSubrange(appIdx...appIdx+1)
}

guard let command = args.first else {
    usage()
    exit(0)
}

if command == "--version" || command == "-v" {
    print("window-tool \(VERSION)")
    exit(0)
}

// Commands that need Accessibility access
let accessibilityCommands: Set<String> = [
    "list", "info", "count", "columnize", "move", "move-by-title",
    "resize", "resize-by-title",
    "snap", "snap-by-title",
    "move-to-screen", "move-to-screen-by-title",
    "maximize", "maximize-by-title",
    "minimize", "minimize-by-title", "restore",
    "save-layout", "restore-layout", "stack", "watch",
    "fullscreen", "fullscreen-by-title",
    "unfullscreen", "unfullscreen-by-title",
    "focus", "focus-by-title", "flash", "flash-by-title",
    "shake", "shake-by-title",
    "highlight", "highlight-by-title",
    "border", "border-by-title", "unborder", "unborder-by-title",
    "dim", "dim-by-title",
    "preview", "preview-by-title",
    "record", "record-by-title",
    "list-open-windows",
    "active-window"
]
// Commands that don't use --app (they enumerate all apps or don't need one)
let appIndependentCommands: Set<String> = ["screens", "active-screen", "active-window", "list-open-windows", "undim", "unborder-all", "help", "--help", "-h"]

do {
    if accessibilityCommands.contains(command) {
        try checkAccessibility()
    }

    if !appIndependentCommands.contains(command) {
        config.bundleId = try resolveAppIdentifier(config.bundleId)
    }

    switch command {
    case "list":
        try listCommand(bundleId: config.bundleId)
    case "info":
        guard args.count >= 2 else {
            fputs("Usage: window-tool info <index|id=N>\n", stderr)
            exit(1)
        }
        try infoCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]))
    case "columnize":
        guard args.count >= 3 else {
            fputs("Usage: window-tool columnize <index|id=N> <index|id=N> [...] [--gap N]\n", stderr)
            exit(1)
        }
        var columnArgs = Array(args.dropFirst())
        var gap = 10
        if let gapIdx = columnArgs.firstIndex(of: "--gap") {
            guard gapIdx + 1 < columnArgs.count else {
                throw WindowToolError.invalidArgument(value: "--gap", label: "flag (requires a value)")
            }
            gap = try parseInt(columnArgs[gapIdx + 1], label: "gap")
            columnArgs.removeSubrange(gapIdx...gapIdx + 1)
        }
        let selectors = try columnArgs.map { try parseWindowSelector($0) }
        try columnizeCommand(bundleId: config.bundleId, selectors: selectors, gap: gap)
    case "count":
        countCommand(bundleId: config.bundleId)
    case "move":
        guard args.count >= 4 else {
            fputs("Usage: window-tool move <index|id=N> <x> <y> [<width> <height>]\n", stderr)
            exit(1)
        }
        let selector = try parseWindowSelector(args[1])
        let x = CGFloat(try parseDouble(args[2], label: "x"))
        let y = CGFloat(try parseDouble(args[3], label: "y"))
        var width: CGFloat? = nil
        var height: CGFloat? = nil
        if args.count >= 6 {
            width = CGFloat(try parseDouble(args[4], label: "width"))
            height = CGFloat(try parseDouble(args[5], label: "height"))
        }
        try moveCommand(bundleId: config.bundleId, selector: selector, x: x, y: y, width: width, height: height)
    case "move-by-title":
        guard args.count >= 4 else {
            fputs("Usage: window-tool move-by-title <pattern> <x> <y> [<width> <height>]\n", stderr)
            exit(1)
        }
        let pattern = args[1]
        let x = CGFloat(try parseDouble(args[2], label: "x"))
        let y = CGFloat(try parseDouble(args[3], label: "y"))
        var width: CGFloat? = nil
        var height: CGFloat? = nil
        if args.count >= 6 {
            width = CGFloat(try parseDouble(args[4], label: "width"))
            height = CGFloat(try parseDouble(args[5], label: "height"))
        }
        try moveCommand(bundleId: config.bundleId, selector: .byTitle(pattern), x: x, y: y, width: width, height: height)
    case "resize":
        guard args.count >= 4 else {
            fputs("Usage: window-tool resize <index|id=N> <width> <height>\n", stderr)
            exit(1)
        }
        let selector = try parseWindowSelector(args[1])
        let width = CGFloat(try parseDouble(args[2], label: "width"))
        let height = CGFloat(try parseDouble(args[3], label: "height"))
        try resizeCommand(bundleId: config.bundleId, selector: selector, width: width, height: height)
    case "resize-by-title":
        guard args.count >= 4 else {
            fputs("Usage: window-tool resize-by-title <pattern> <width> <height>\n", stderr)
            exit(1)
        }
        try resizeCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), width: CGFloat(try parseDouble(args[2], label: "width")), height: CGFloat(try parseDouble(args[3], label: "height")))
    case "snap":
        guard args.count >= 3 else {
            fputs("Usage: window-tool snap <index|id=N> <position>\nPositions: \(SnapPosition.allNames)\n", stderr)
            exit(1)
        }
        guard let position = SnapPosition(rawValue: args[2]) else {
            fputs("Error: Unknown snap position '\(args[2])'. Valid: \(SnapPosition.allNames)\n", stderr)
            exit(1)
        }
        try snapCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]), position: position)
    case "snap-by-title":
        guard args.count >= 3 else {
            fputs("Usage: window-tool snap-by-title <pattern> <position>\nPositions: \(SnapPosition.allNames)\n", stderr)
            exit(1)
        }
        guard let position = SnapPosition(rawValue: args[2]) else {
            fputs("Error: Unknown snap position '\(args[2])'. Valid: \(SnapPosition.allNames)\n", stderr)
            exit(1)
        }
        try snapCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), position: position)
    case "move-to-screen":
        guard args.count >= 3 else {
            fputs("Usage: window-tool move-to-screen <index|id=N> <screen>\n", stderr)
            exit(1)
        }
        try moveToScreenCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]), screenIndex: try parseInt(args[2], label: "screen"))
    case "move-to-screen-by-title":
        guard args.count >= 3 else {
            fputs("Usage: window-tool move-to-screen-by-title <pattern> <screen>\n", stderr)
            exit(1)
        }
        try moveToScreenCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), screenIndex: try parseInt(args[2], label: "screen"))
    case "maximize":
        guard args.count >= 2 else {
            fputs("Usage: window-tool maximize <index|id=N>\n", stderr)
            exit(1)
        }
        try maximizeCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]))
    case "maximize-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool maximize-by-title <pattern>\n", stderr)
            exit(1)
        }
        try maximizeCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "minimize":
        guard args.count >= 2 else {
            fputs("Usage: window-tool minimize <index|id=N>\n", stderr)
            exit(1)
        }
        try minimizeCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]))
    case "minimize-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool minimize-by-title <pattern>\n", stderr)
            exit(1)
        }
        try minimizeCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "restore":
        try restoreCommand(bundleId: config.bundleId)
    case "save-layout":
        guard args.count >= 2 else {
            fputs("Usage: window-tool save-layout <file>\n", stderr)
            exit(1)
        }
        try saveLayoutCommand(bundleId: config.bundleId, filePath: args[1])
    case "restore-layout":
        guard args.count >= 2 else {
            fputs("Usage: window-tool restore-layout <file>\n", stderr)
            exit(1)
        }
        try restoreLayoutCommand(filePath: args[1])
    case "stack":
        let offset = args.count >= 2 ? try parseInt(args[1], label: "offset") : 30
        try stackCommand(bundleId: config.bundleId, offsetStep: offset)
    case "watch":
        let interval = args.count >= 2 ? try parseDouble(args[1], label: "interval") : 1.0
        try watchCommand(bundleId: config.bundleId, interval: interval)
    case "focus":
        guard args.count >= 2 else {
            fputs("Usage: window-tool focus <index|id=N>\n", stderr)
            exit(1)
        }
        try focusCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]))
    case "focus-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool focus-by-title <pattern>\n", stderr)
            exit(1)
        }
        try focusCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "fullscreen":
        guard args.count >= 2 else {
            fputs("Usage: window-tool fullscreen <index|id=N>\n", stderr)
            exit(1)
        }
        try fullscreenCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]))
    case "fullscreen-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool fullscreen-by-title <pattern>\n", stderr)
            exit(1)
        }
        try fullscreenCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "unfullscreen":
        guard args.count >= 2 else {
            fputs("Usage: window-tool unfullscreen <index|id=N>\n", stderr)
            exit(1)
        }
        try unfullscreenCommand(bundleId: config.bundleId, selector: try parseWindowSelector(args[1]))
    case "unfullscreen-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool unfullscreen-by-title <pattern>\n", stderr)
            exit(1)
        }
        try unfullscreenCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "shake":
        guard args.count >= 2 else {
            fputs("Usage: window-tool shake <index|id=N> [offset] [count] [delay]\n", stderr)
            exit(1)
        }
        let selector = try parseWindowSelector(args[1])
        let offset = args.count >= 3 ? try parseInt(args[2], label: "offset") : 12
        let count = args.count >= 4 ? try parseInt(args[3], label: "count") : 6
        let delay = args.count >= 5 ? try parseDouble(args[4], label: "delay") : 0.04
        try shakeCommand(bundleId: config.bundleId, selector: selector, offset: offset, count: count, delay: delay)
    case "shake-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool shake-by-title <pattern> [offset] [count] [delay]\n", stderr)
            exit(1)
        }
        let selector = WindowSelector.byTitle(args[1])
        let offset = args.count >= 3 ? try parseInt(args[2], label: "offset") : 12
        let count = args.count >= 4 ? try parseInt(args[3], label: "count") : 6
        let delay = args.count >= 5 ? try parseDouble(args[4], label: "delay") : 0.04
        try shakeCommand(bundleId: config.bundleId, selector: selector, offset: offset, count: count, delay: delay)
    case "flash":
        guard args.count >= 2 else {
            fputs("Usage: window-tool flash <index|id=N> [--color green] [--count 1]\n", stderr)
            exit(1)
        }
        var flashArgs = Array(args.dropFirst())
        let selector = try parseWindowSelector(flashArgs.removeFirst())
        let flags = try parseFlashFlags(&flashArgs)
        try flashCommand(bundleId: config.bundleId, selector: selector, color: flags.color, count: flags.count)
    case "flash-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool flash-by-title <pattern> [--color green] [--count 1]\n", stderr)
            exit(1)
        }
        var flashArgs = Array(args.dropFirst())
        let pattern = flashArgs.removeFirst()
        let flags = try parseFlashFlags(&flashArgs)
        try flashCommand(bundleId: config.bundleId, selector: .byTitle(pattern), color: flags.color, count: flags.count)
    case "highlight":
        guard args.count >= 2 else {
            fputs("Usage: window-tool highlight <window> [--color <color>] [--duration <seconds>]\n", stderr)
            exit(1)
        }
        let selector = try parseWindowSelector(args[1])
        let hlFlags = try parseHighlightFlags(Array(args.dropFirst()))
        try highlightCommand(bundleId: config.bundleId, selector: selector, color: hlFlags.color, duration: hlFlags.duration)
    case "highlight-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool highlight-by-title <pattern> [--color <color>] [--duration <seconds>]\n", stderr)
            exit(1)
        }
        let hlFlags = try parseHighlightFlags(Array(args.dropFirst()))
        try highlightCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), color: hlFlags.color, duration: hlFlags.duration)
    case "border":
        guard args.count >= 2 else {
            fputs("Usage: window-tool border <window> [--color <color>] [--width <pixels>]\n", stderr)
            exit(1)
        }
        let selector = try parseWindowSelector(args[1])
        let borderFlags = try parseBorderFlags(Array(args.dropFirst()))
        try borderCommand(bundleId: config.bundleId, selector: selector, color: borderFlags.color, width: borderFlags.width)
    case "border-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool border-by-title <pattern> [--color <color>] [--width <pixels>]\n", stderr)
            exit(1)
        }
        let borderFlags = try parseBorderFlags(Array(args.dropFirst()))
        try borderCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), color: borderFlags.color, width: borderFlags.width)
    case "unborder":
        if args.count >= 2 {
            let selector = try parseWindowSelector(args[1])
            unborderCommand(bundleId: config.bundleId, selector: selector)
        } else {
            unborderCommand(bundleId: config.bundleId)
        }
    case "unborder-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool unborder-by-title <pattern>\n", stderr)
            exit(1)
        }
        unborderCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "unborder-all":
        unborderAllCommand()
    case "dim":
        guard args.count >= 2 else {
            fputs("Usage: window-tool dim <window> [--opacity 0.5] [--duration 0]\n", stderr)
            exit(1)
        }
        let selector = try parseWindowSelector(args[1])
        let dimFlags = try parseDimFlags(Array(args.dropFirst()))
        try dimCommand(bundleId: config.bundleId, selector: selector, opacity: dimFlags.opacity, duration: dimFlags.duration)
    case "dim-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool dim-by-title <pattern> [--opacity 0.5] [--duration 0]\n", stderr)
            exit(1)
        }
        let dimFlags = try parseDimFlags(Array(args.dropFirst()))
        try dimCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), opacity: dimFlags.opacity, duration: dimFlags.duration)
    case "undim":
        try undimCommand()
    case "preview":
        guard args.count >= 2 else {
            fputs("Usage: window-tool preview <index|id=N> [--output <path>]\n", stderr)
            exit(1)
        }
        var previewArgs = Array(args.dropFirst())
        let previewSelector = try parseWindowSelector(previewArgs.removeFirst())
        let outputPath = try parsePreviewFlags(previewArgs)
        try previewCommand(bundleId: config.bundleId, selector: previewSelector, outputPath: outputPath)
    case "preview-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool preview-by-title <pattern> [--output <path>]\n", stderr)
            exit(1)
        }
        var previewArgs = Array(args.dropFirst())
        let pattern = previewArgs.removeFirst()
        let outputPath = try parsePreviewFlags(previewArgs)
        try previewCommand(bundleId: config.bundleId, selector: .byTitle(pattern), outputPath: outputPath)
    case "record":
        guard args.count >= 2 else {
            fputs("Usage: window-tool record <index|id=N> --output <path> [--fps 30] [--duration N]\n", stderr)
            exit(1)
        }
        var recordArgs = Array(args.dropFirst())
        let recordSelector = try parseWindowSelector(recordArgs.removeFirst())
        let recordFlags = try parseRecordFlags(recordArgs)
        try recordCommand(bundleId: config.bundleId, selector: recordSelector, output: recordFlags.output, fps: recordFlags.fps, duration: recordFlags.duration, countdown: recordFlags.countdown, border: recordFlags.border)
    case "record-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool record-by-title <pattern> --output <path> [--fps 30] [--duration N]\n", stderr)
            exit(1)
        }
        var recordArgs = Array(args.dropFirst())
        let pattern = recordArgs.removeFirst()
        let recordFlags = try parseRecordFlags(recordArgs)
        try recordCommand(bundleId: config.bundleId, selector: .byTitle(pattern), output: recordFlags.output, fps: recordFlags.fps, duration: recordFlags.duration, countdown: recordFlags.countdown, border: recordFlags.border)
    case "list-open-windows":
        listOpenWindowsCommand()
    case "screens":
        screensCommand()
    case "active-screen":
        activeScreenCommand()
    case "active-window":
        try activeWindowCommand()
    case "help", "--help", "-h":
        usage()
    default:
        fputs("Unknown command: \(command)\n", stderr)
        usage()
        exit(1)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
