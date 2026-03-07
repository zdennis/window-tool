import Cocoa
import Foundation

let VERSION = "0.3.0"

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
    case windowIndexOutOfRange(index: Int, count: Int)
    case noWindowMatchingTitle(String)
    case screenIndexOutOfRange(index: Int, count: Int)
    case accessibilityNotEnabled
    case invalidArgument(value: String, label: String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let id):
            return "Application not found: \(id)"
        case .windowIndexOutOfRange(let index, let count):
            return "Window index \(index) out of range\(count == 0 ? " (no windows)" : " (0..\(count - 1))")"
        case .noWindowMatchingTitle(let pattern):
            return "No window found matching '\(pattern)'"
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

// MARK: - Accessibility Helpers

/// Returns the AXUIElement for a running application matching the given bundle identifier.
/// Returns nil if no running application with that bundle ID is found.
func getAppElement(bundleId: String) -> AXUIElement? {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    guard let app = apps.first else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

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

        result.append(WindowInfo(element: window, id: index, title: title, position: position, size: size))
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
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            let isMain = (screen == NSScreen.main)
            let containsMouse = frame.contains(mouseLocation)
            var flags: [String] = []
            if isMain { flags.append("main") }
            if containsMouse { flags.append("mouse") }
            let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ","))]"
            print("\(index)\t\(Int(frame.origin.x)),\(Int(frame.origin.y))\t\(Int(frame.width))x\(Int(frame.height))\t\(Int(visible.origin.x)),\(Int(visible.origin.y))\t\(Int(visible.width))x\(Int(visible.height))\(flagStr)")
        }
    }
}

/// Prints the visible bounds of the screen containing the mouse cursor.
/// Output: tab-separated x, y (top-left origin), width, height of the usable area.
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
/// Output columns (tab-separated): index, position (x,y), size (WxH), title.
func listCommand(bundleId: String) throws {
    let app = try requireApp(bundleId)
    let windows = getWindows(appElement: app)
    if config.jsonOutput {
        let items = windows.map { w in
            ["index": w.id, "x": Int(w.position.x), "y": Int(w.position.y),
             "width": Int(w.size.width), "height": Int(w.size.height), "title": w.title] as [String: Any]
        }
        printJSON(items)
    } else {
        for w in windows {
            print("\(w.id)\t\(Int(w.position.x)),\(Int(w.position.y))\t\(Int(w.size.width))x\(Int(w.size.height))\t\(w.title)")
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

/// Prints detailed info for a single window by index.
func infoCommand(bundleId: String, index: Int) throws {
    let w = try resolveWindow(bundleId: bundleId, selector: .byIndex(index))

    var minimizedRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w.element, kAXMinimizedAttribute as CFString, &minimizedRef)
    let minimized = (minimizedRef as? Bool) ?? false

    var fullscreenRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w.element, "AXFullScreen" as CFString, &fullscreenRef)
    let fullscreen = (fullscreenRef as? Bool) ?? false

    if config.jsonOutput {
        printJSON(["index": w.id, "title": w.title,
                   "x": Int(w.position.x), "y": Int(w.position.y),
                   "width": Int(w.size.width), "height": Int(w.size.height),
                   "minimized": minimized, "fullscreen": fullscreen] as [String: Any])
    } else {
        print("index:\t\(w.id)")
        print("title:\t\(w.title)")
        print("position:\t\(Int(w.position.x)),\(Int(w.position.y))")
        print("size:\t\(Int(w.size.width))x\(Int(w.size.height))")
        print("minimized:\t\(minimized)")
        print("fullscreen:\t\(fullscreen)")
    }
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
    Usage: window-tool [--app <bundle-id>] <command> [args...]

    Commands:
      active-screen                            Print active screen bounds (x, y, width, height)
      count                                    Print number of windows
      focus <index>                            Bring window to front by index
      focus-by-title <pattern>                 Bring window to front by title match
      fullscreen <index>                       Enter macOS fullscreen mode
      fullscreen-by-title <pattern>            Enter fullscreen by title match
      info <index>                             Show detailed info for a window
      list                                     List all windows with index, position, size, and title
      list-open-windows                        List apps with open windows
      maximize <index>                         Maximize window to fill screen
      maximize-by-title <pattern>              Maximize windows matching title
      minimize <index>                         Minimize a window by index
      minimize-by-title <pattern>              Minimize a window by title match
      move <index> <x> <y> [<w> <h>]           Move/resize window by index
      move-by-title <pattern> <x> <y> [<w> <h>]  Move/resize windows matching title
      move-to-screen <index> <screen>          Move window to a different display
      move-to-screen-by-title <pattern> <screen>  Move window to display by title
      resize <index> <width> <height>          Resize window by index
      resize-by-title <pattern> <width> <height>  Resize windows matching title
      restore                                  Restore all minimized windows
      restore-layout <file>                    Restore window layout from a JSON file
      save-layout <file>                       Save window layout to a JSON file
      screens                                  List all displays with bounds
      shake <index> [offset] [count] [delay]   Shake a window by index
      shake-by-title <pattern> [offset] [count] [delay]  Shake a window by title match
      snap <index> <position>                  Snap window to screen region
      snap-by-title <pattern> <position>       Snap window to screen region by title
      stack [offset]                           Cascade windows with offset (default: 30)
      unfullscreen <index>                     Exit macOS fullscreen mode
      unfullscreen-by-title <pattern>          Exit fullscreen by title match
      watch [interval]                         Watch for window changes (default: 1.0s)

    Snap positions:
      left, right, top, bottom, top-left, top-right,
      bottom-left, bottom-right, center, maximize

    Options:
      --app <bundle-id>   Target application (default: com.googlecode.iterm2)
      --json              Output in JSON format
      --version, -v       Print version and exit

    Examples:
      window-tool list
      window-tool move 0 100 50 1200 900
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
        fputs("Error: --app requires a bundle identifier\n", stderr)
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
    "list", "info", "count", "move", "move-by-title",
    "resize", "resize-by-title",
    "snap", "snap-by-title",
    "move-to-screen", "move-to-screen-by-title",
    "maximize", "maximize-by-title",
    "minimize", "minimize-by-title", "restore",
    "save-layout", "restore-layout", "stack", "watch",
    "fullscreen", "fullscreen-by-title",
    "unfullscreen", "unfullscreen-by-title",
    "focus", "focus-by-title", "shake", "shake-by-title",
    "list-open-windows"
]
do {
    if accessibilityCommands.contains(command) {
        try checkAccessibility()
    }

    switch command {
    case "list":
        try listCommand(bundleId: config.bundleId)
    case "info":
        guard args.count >= 2 else {
            fputs("Usage: window-tool info <index>\n", stderr)
            exit(1)
        }
        try infoCommand(bundleId: config.bundleId, index: try parseInt(args[1], label: "index"))
    case "count":
        countCommand(bundleId: config.bundleId)
    case "move":
        guard args.count >= 4 else {
            fputs("Usage: window-tool move <index> <x> <y> [<width> <height>]\n", stderr)
            exit(1)
        }
        let index = try parseInt(args[1], label: "index")
        let x = CGFloat(try parseDouble(args[2], label: "x"))
        let y = CGFloat(try parseDouble(args[3], label: "y"))
        var width: CGFloat? = nil
        var height: CGFloat? = nil
        if args.count >= 6 {
            width = CGFloat(try parseDouble(args[4], label: "width"))
            height = CGFloat(try parseDouble(args[5], label: "height"))
        }
        try moveCommand(bundleId: config.bundleId, selector: .byIndex(index), x: x, y: y, width: width, height: height)
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
            fputs("Usage: window-tool resize <index> <width> <height>\n", stderr)
            exit(1)
        }
        let index = try parseInt(args[1], label: "index")
        let width = CGFloat(try parseDouble(args[2], label: "width"))
        let height = CGFloat(try parseDouble(args[3], label: "height"))
        try resizeCommand(bundleId: config.bundleId, selector: .byIndex(index), width: width, height: height)
    case "resize-by-title":
        guard args.count >= 4 else {
            fputs("Usage: window-tool resize-by-title <pattern> <width> <height>\n", stderr)
            exit(1)
        }
        try resizeCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), width: CGFloat(try parseDouble(args[2], label: "width")), height: CGFloat(try parseDouble(args[3], label: "height")))
    case "snap":
        guard args.count >= 3 else {
            fputs("Usage: window-tool snap <index> <position>\nPositions: \(SnapPosition.allNames)\n", stderr)
            exit(1)
        }
        guard let position = SnapPosition(rawValue: args[2]) else {
            fputs("Error: Unknown snap position '\(args[2])'. Valid: \(SnapPosition.allNames)\n", stderr)
            exit(1)
        }
        try snapCommand(bundleId: config.bundleId, selector: .byIndex(try parseInt(args[1], label: "index")), position: position)
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
            fputs("Usage: window-tool move-to-screen <index> <screen>\n", stderr)
            exit(1)
        }
        try moveToScreenCommand(bundleId: config.bundleId, selector: .byIndex(try parseInt(args[1], label: "index")), screenIndex: try parseInt(args[2], label: "screen"))
    case "move-to-screen-by-title":
        guard args.count >= 3 else {
            fputs("Usage: window-tool move-to-screen-by-title <pattern> <screen>\n", stderr)
            exit(1)
        }
        try moveToScreenCommand(bundleId: config.bundleId, selector: .byTitle(args[1]), screenIndex: try parseInt(args[2], label: "screen"))
    case "maximize":
        guard args.count >= 2 else {
            fputs("Usage: window-tool maximize <index>\n", stderr)
            exit(1)
        }
        try maximizeCommand(bundleId: config.bundleId, selector: .byIndex(try parseInt(args[1], label: "index")))
    case "maximize-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool maximize-by-title <pattern>\n", stderr)
            exit(1)
        }
        try maximizeCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "minimize":
        guard args.count >= 2 else {
            fputs("Usage: window-tool minimize <index>\n", stderr)
            exit(1)
        }
        try minimizeCommand(bundleId: config.bundleId, selector: .byIndex(try parseInt(args[1], label: "index")))
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
            fputs("Usage: window-tool focus <index>\n", stderr)
            exit(1)
        }
        try focusCommand(bundleId: config.bundleId, selector: .byIndex(try parseInt(args[1], label: "index")))
    case "focus-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool focus-by-title <pattern>\n", stderr)
            exit(1)
        }
        try focusCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "fullscreen":
        guard args.count >= 2 else {
            fputs("Usage: window-tool fullscreen <index>\n", stderr)
            exit(1)
        }
        try fullscreenCommand(bundleId: config.bundleId, selector: .byIndex(try parseInt(args[1], label: "index")))
    case "fullscreen-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool fullscreen-by-title <pattern>\n", stderr)
            exit(1)
        }
        try fullscreenCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "unfullscreen":
        guard args.count >= 2 else {
            fputs("Usage: window-tool unfullscreen <index>\n", stderr)
            exit(1)
        }
        try unfullscreenCommand(bundleId: config.bundleId, selector: .byIndex(try parseInt(args[1], label: "index")))
    case "unfullscreen-by-title":
        guard args.count >= 2 else {
            fputs("Usage: window-tool unfullscreen-by-title <pattern>\n", stderr)
            exit(1)
        }
        try unfullscreenCommand(bundleId: config.bundleId, selector: .byTitle(args[1]))
    case "shake":
        guard args.count >= 2 else {
            fputs("Usage: window-tool shake <index> [offset] [count] [delay]\n", stderr)
            exit(1)
        }
        let selector = WindowSelector.byIndex(try parseInt(args[1], label: "index"))
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
    case "list-open-windows":
        listOpenWindowsCommand()
    case "screens":
        screensCommand()
    case "active-screen":
        activeScreenCommand()
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
