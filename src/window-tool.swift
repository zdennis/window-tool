import Cocoa
import Foundation

// MARK: - JSON Output

var jsonOutput = false

func printJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

// MARK: - Argument Parsing Helpers

func parseInt(_ s: String, label: String) -> Int {
    guard let v = Int(s) else {
        fputs("Error: '\(s)' is not a valid \(label)\n", stderr)
        exit(1)
    }
    return v
}

func parseDouble(_ s: String, label: String) -> Double {
    guard let v = Double(s) else {
        fputs("Error: '\(s)' is not a valid \(label)\n", stderr)
        exit(1)
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

// MARK: - Screen Helpers

/// Prints info for all connected displays.
/// Output columns: index, frame origin, frame size, visible origin, visible size, and flags ([main], [mouse]).
func screensCommand() {
    let mouseLocation = NSEvent.mouseLocation
    if jsonOutput {
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
    if jsonOutput {
        printJSON(["x": Int(frame.origin.x), "y": Int(topLeftY),
                   "width": Int(visible.width), "height": Int(visible.height)])
    } else {
        print("\(Int(frame.origin.x))\t\(Int(topLeftY))\t\(Int(visible.width))\t\(Int(visible.height))")
    }
}

// MARK: - Accessibility Check

/// Checks if the process has Accessibility API access and exits with a helpful message if not.
func checkAccessibility() {
    let trusted = AXIsProcessTrusted()
    if !trusted {
        fputs("Error: Accessibility access is not enabled.\n", stderr)
        fputs("Grant access in System Settings > Privacy & Security > Accessibility.\n", stderr)
        fputs("Add this terminal app or the window-tool binary.\n", stderr)
        exit(1)
    }
}

// MARK: - Commands

/// Lists all windows for the given application.
/// Output columns (tab-separated): index, position (x,y), size (WxH), title.
func listCommand(bundleId: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    if jsonOutput {
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

/// Moves (and optionally resizes) a window by its index.
/// If width and height are provided, the window is also resized.
func moveCommand(bundleId: String, index: Int, x: CGFloat, y: CGFloat, width: CGFloat?, height: CGFloat?) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard index >= 0 && index < windows.count else {
        fputs("Error: Window index \(index) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    let window = windows[index]
    moveWindow(window.element, x: x, y: y)
    if let w = width, let h = height {
        resizeWindow(window.element, width: w, height: h)
    }
}

/// Moves (and optionally resizes) all windows whose title contains the given pattern.
/// Uses substring matching. Prints the number of windows moved.
func moveByTitleCommand(bundleId: String, titlePattern: String, x: CGFloat, y: CGFloat, width: CGFloat?, height: CGFloat?) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    let matching = windows.filter { $0.title.contains(titlePattern) }
    if matching.isEmpty {
        fputs("Error: No window found matching '\(titlePattern)'\n", stderr)
        exit(1)
    }
    for window in matching {
        moveWindow(window.element, x: x, y: y)
        if let w = width, let h = height {
            resizeWindow(window.element, width: w, height: h)
        }
    }
    print("Moved \(matching.count) window(s) matching '\(titlePattern)'")
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
    if jsonOutput {
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

/// Brings a window to the front by its index.
/// Activates the application and raises the specific window.
func focusCommand(bundleId: String, index: Int) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard index >= 0 && index < windows.count else {
        fputs("Error: Window index \(index) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    let window = windows[index]
    // Bring app to front
    let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    runningApps.first?.activate()
    // Raise the specific window
    AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
}

/// Brings the first window whose title contains the given pattern to the front.
/// Activates the application and raises the matching window.
func focusByTitleCommand(bundleId: String, titlePattern: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard let window = windows.first(where: { $0.title.contains(titlePattern) }) else {
        fputs("Error: No window found matching '\(titlePattern)'\n", stderr)
        exit(1)
    }
    let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    runningApps.first?.activate()
    AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
}

/// Shakes a window horizontally by its index to draw attention.
/// - Parameters:
///   - offset: Horizontal pixel displacement per shake (default: 12).
///   - count: Number of shake cycles (default: 6).
///   - shakeDelay: Seconds between each movement (default: 0.04).
/// The window is restored to its original position after shaking.
func shakeCommand(bundleId: String, index: Int, offset: Int, count: Int, delay shakeDelay: Double) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard index >= 0 && index < windows.count else {
        fputs("Error: Window index \(index) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    let window = windows[index]
    let originalX = window.position.x
    let originalY = window.position.y

    for _ in 0..<count {
        moveWindow(window.element, x: originalX + CGFloat(offset), y: originalY)
        Thread.sleep(forTimeInterval: shakeDelay)
        moveWindow(window.element, x: originalX - CGFloat(offset), y: originalY)
        Thread.sleep(forTimeInterval: shakeDelay)
    }
    // Restore original position
    moveWindow(window.element, x: originalX, y: originalY)
}

/// Shakes the first window whose title contains the given pattern.
/// Same behavior as `shakeCommand` but targets by title substring match.
func shakeByTitleCommand(bundleId: String, titlePattern: String, offset: Int, count: Int, delay shakeDelay: Double) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard let window = windows.first(where: { $0.title.contains(titlePattern) }) else {
        fputs("Error: No window found matching '\(titlePattern)'\n", stderr)
        exit(1)
    }
    let originalX = window.position.x
    let originalY = window.position.y

    for _ in 0..<count {
        moveWindow(window.element, x: originalX + CGFloat(offset), y: originalY)
        Thread.sleep(forTimeInterval: shakeDelay)
        moveWindow(window.element, x: originalX - CGFloat(offset), y: originalY)
        Thread.sleep(forTimeInterval: shakeDelay)
    }
    moveWindow(window.element, x: originalX, y: originalY)
}

/// Resizes a window by its index without changing its position.
func resizeCommand(bundleId: String, index: Int, width: CGFloat, height: CGFloat) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard index >= 0 && index < windows.count else {
        fputs("Error: Window index \(index) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    resizeWindow(windows[index].element, width: width, height: height)
}

/// Resizes all windows whose title contains the given pattern without changing their position.
func resizeByTitleCommand(bundleId: String, titlePattern: String, width: CGFloat, height: CGFloat) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    let matching = windows.filter { $0.title.contains(titlePattern) }
    if matching.isEmpty {
        fputs("Error: No window found matching '\(titlePattern)'\n", stderr)
        exit(1)
    }
    for window in matching {
        resizeWindow(window.element, width: width, height: height)
    }
    print("Resized \(matching.count) window(s) matching '\(titlePattern)'")
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

let snapPositions = ["left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right", "center", "maximize"]

/// Snaps a window to a named screen region by index.
func snapCommand(bundleId: String, index: Int, position: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard index >= 0 && index < windows.count else {
        fputs("Error: Window index \(index) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    let window = windows[index]
    snapWindow(window, position: position)
}

/// Snaps the first window matching a title pattern to a named screen region.
func snapByTitleCommand(bundleId: String, titlePattern: String, position: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard let window = windows.first(where: { $0.title.contains(titlePattern) }) else {
        fputs("Error: No window found matching '\(titlePattern)'\n", stderr)
        exit(1)
    }
    snapWindow(window, position: position)
}

func snapWindow(_ window: WindowInfo, position: String) {
    let s = screenBoundsForWindow(window)
    let halfW = s.width / 2
    let halfH = s.height / 2

    switch position {
    case "left":
        moveWindow(window.element, x: s.x, y: s.y)
        resizeWindow(window.element, width: halfW, height: s.height)
    case "right":
        moveWindow(window.element, x: s.x + halfW, y: s.y)
        resizeWindow(window.element, width: halfW, height: s.height)
    case "top":
        moveWindow(window.element, x: s.x, y: s.y)
        resizeWindow(window.element, width: s.width, height: halfH)
    case "bottom":
        moveWindow(window.element, x: s.x, y: s.y + halfH)
        resizeWindow(window.element, width: s.width, height: halfH)
    case "top-left":
        moveWindow(window.element, x: s.x, y: s.y)
        resizeWindow(window.element, width: halfW, height: halfH)
    case "top-right":
        moveWindow(window.element, x: s.x + halfW, y: s.y)
        resizeWindow(window.element, width: halfW, height: halfH)
    case "bottom-left":
        moveWindow(window.element, x: s.x, y: s.y + halfH)
        resizeWindow(window.element, width: halfW, height: halfH)
    case "bottom-right":
        moveWindow(window.element, x: s.x + halfW, y: s.y + halfH)
        resizeWindow(window.element, width: halfW, height: halfH)
    case "center":
        let w = window.size.width
        let h = window.size.height
        moveWindow(window.element, x: s.x + (s.width - w) / 2, y: s.y + (s.height - h) / 2)
    case "maximize":
        moveWindow(window.element, x: s.x, y: s.y)
        resizeWindow(window.element, width: s.width, height: s.height)
    default:
        fputs("Error: Unknown snap position '\(position)'. Valid: \(snapPositions.joined(separator: ", "))\n", stderr)
        exit(1)
    }
}

/// Moves a window to a different screen by index, preserving its relative position within the visible area.
func moveToScreenCommand(bundleId: String, windowIndex: Int, screenIndex: Int) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard windowIndex >= 0 && windowIndex < windows.count else {
        fputs("Error: Window index \(windowIndex) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    guard screenIndex >= 0 && screenIndex < NSScreen.screens.count else {
        fputs("Error: Screen index \(screenIndex) out of range (0..\(NSScreen.screens.count - 1))\n", stderr)
        exit(1)
    }
    let window = windows[windowIndex]
    let targetScreen = NSScreen.screens[screenIndex]
    let frame = targetScreen.frame
    let visible = targetScreen.visibleFrame
    let topLeftY = frame.origin.y + frame.height - (visible.origin.y + visible.height)
    moveWindow(window.element, x: visible.origin.x, y: topLeftY)
}

/// Moves the first window matching a title pattern to a different screen.
func moveToScreenByTitleCommand(bundleId: String, titlePattern: String, screenIndex: Int) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard let window = windows.first(where: { $0.title.contains(titlePattern) }) else {
        fputs("Error: No window found matching '\(titlePattern)'\n", stderr)
        exit(1)
    }
    guard screenIndex >= 0 && screenIndex < NSScreen.screens.count else {
        fputs("Error: Screen index \(screenIndex) out of range (0..\(NSScreen.screens.count - 1))\n", stderr)
        exit(1)
    }
    let targetScreen = NSScreen.screens[screenIndex]
    let frame = targetScreen.frame
    let visible = targetScreen.visibleFrame
    let topLeftY = frame.origin.y + frame.height - (visible.origin.y + visible.height)
    moveWindow(window.element, x: visible.origin.x, y: topLeftY)
}

/// Minimizes a window by its index.
func minimizeCommand(bundleId: String, index: Int) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard index >= 0 && index < windows.count else {
        fputs("Error: Window index \(index) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    AXUIElementSetAttributeValue(windows[index].element, kAXMinimizedAttribute as CFString, true as CFTypeRef)
}

/// Minimizes the first window matching a title pattern.
func minimizeByTitleCommand(bundleId: String, titlePattern: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard let window = windows.first(where: { $0.title.contains(titlePattern) }) else {
        fputs("Error: No window found matching '\(titlePattern)'\n", stderr)
        exit(1)
    }
    AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, true as CFTypeRef)
}

/// Restores (unminimizes) all minimized windows for the given application.
func restoreCommand(bundleId: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
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
func infoCommand(bundleId: String, index: Int) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    guard index >= 0 && index < windows.count else {
        fputs("Error: Window index \(index) out of range (0..\(windows.count - 1))\n", stderr)
        exit(1)
    }
    let w = windows[index]

    var minimizedRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w.element, kAXMinimizedAttribute as CFString, &minimizedRef)
    let minimized = (minimizedRef as? Bool) ?? false

    var fullscreenRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w.element, "AXFullScreen" as CFString, &fullscreenRef)
    let fullscreen = (fullscreenRef as? Bool) ?? false

    if jsonOutput {
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

/// Saves the current window layout for an application to a JSON file.
func saveLayoutCommand(bundleId: String, filePath: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    let items = windows.map { w in
        ["index": w.id, "title": w.title,
         "x": Int(w.position.x), "y": Int(w.position.y),
         "width": Int(w.size.width), "height": Int(w.size.height)] as [String: Any]
    }
    let layout: [String: Any] = ["bundle_id": bundleId, "windows": items]
    guard let data = try? JSONSerialization.data(withJSONObject: layout, options: [.prettyPrinted, .sortedKeys]) else {
        fputs("Error: Failed to serialize layout\n", stderr)
        exit(1)
    }
    let url = URL(fileURLWithPath: filePath)
    do {
        try data.write(to: url)
        print("Saved \(windows.count) window(s) to \(filePath)")
    } catch {
        fputs("Error: Could not write to \(filePath): \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

/// Restores window positions and sizes from a previously saved layout file.
/// Matches windows by title. Windows that can't be matched are skipped.
func restoreLayoutCommand(filePath: String) {
    let url = URL(fileURLWithPath: filePath)
    guard let data = try? Data(contentsOf: url),
          let layout = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let bundleId = layout["bundle_id"] as? String,
          let savedWindows = layout["windows"] as? [[String: Any]] else {
        fputs("Error: Could not read layout from \(filePath)\n", stderr)
        exit(1)
    }
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let currentWindows = getWindows(appElement: app)
    var restored = 0
    for saved in savedWindows {
        guard let title = saved["title"] as? String,
              let x = saved["x"] as? Int,
              let y = saved["y"] as? Int,
              let width = saved["width"] as? Int,
              let height = saved["height"] as? Int else { continue }
        if let match = currentWindows.first(where: { $0.title == title }) {
            moveWindow(match.element, x: CGFloat(x), y: CGFloat(y))
            resizeWindow(match.element, width: CGFloat(width), height: CGFloat(height))
            restored += 1
        }
    }
    print("Restored \(restored)/\(savedWindows.count) window(s) for \(bundleId)")
}

/// Cascades all windows for an application, offsetting each by a fixed amount.
func stackCommand(bundleId: String, offsetStep: Int) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
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
func watchCommand(bundleId: String, interval: Double) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }

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
        for (i, w) in windows.enumerated() {
            print("\(i)\t\(w.x),\(w.y)\t\(w.width)x\(w.height)\t\(w.title)")
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
            print("---")
            printState(current)
            fflush(stdout)
            previous = current
        }
    }
}

/// Prints the number of windows for the given application. Prints "0" if the app is not found.
func countCommand(bundleId: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        if jsonOutput { printJSON(["count": 0]) } else { print("0") }
        return
    }
    let windows = getWindows(appElement: app)
    if jsonOutput { printJSON(["count": windows.count]) } else { print("\(windows.count)") }
}

// MARK: - Main

/// Prints the CLI usage/help text.
func usage() {
    let help = """
    Usage: window-tool [--app <bundle-id>] <command> [args...]

    Commands:
      list                                     List all windows with index, position, size, and title
      info <index>                             Show detailed info for a window
      count                                    Print number of windows
      move <index> <x> <y> [<width> <height>]  Move/resize window by index
      move-by-title <pattern> <x> <y> [<width> <height>]  Move/resize windows matching title
      resize <index> <width> <height>          Resize window by index
      resize-by-title <pattern> <width> <height>  Resize windows matching title
      snap <index> <position>                  Snap window to screen region
      snap-by-title <pattern> <position>       Snap window to screen region by title
      move-to-screen <index> <screen>          Move window to a different display
      move-to-screen-by-title <pattern> <screen>  Move window to display by title
      minimize <index>                         Minimize a window by index
      minimize-by-title <pattern>              Minimize a window by title match
      restore                                  Restore all minimized windows
      save-layout <file>                       Save window layout to a JSON file
      restore-layout <file>                    Restore window layout from a JSON file
      stack [offset]                           Cascade windows with offset (default: 30)
      watch [interval]                         Watch for window changes (default: 1.0s)

    Snap positions:
      left, right, top, bottom, top-left, top-right,
      bottom-left, bottom-right, center, maximize
      focus <index>                             Bring window to front by index
      focus-by-title <pattern>                 Bring window to front by title match
      shake <index> [offset] [count] [delay]   Shake a window by index
      shake-by-title <pattern> [offset] [count] [delay]  Shake a window by title match
      list-open-windows                        List bundle IDs of apps with open windows
      screens                                  List all displays with bounds
      active-screen                            Print active screen bounds (x, y, width, height)

    Options:
      --app <bundle-id>   Target application (default: com.googlecode.iterm2)
      --json              Output in JSON format

    Examples:
      window-tool list
      window-tool move 0 100 50 1200 900
      window-tool move-by-title "my-notes" 0 0 1400 1000
    """
    print(help)
}

var args = Array(CommandLine.arguments.dropFirst())
var bundleId = "com.googlecode.iterm2"

// Parse --json flag
if let jsonIdx = args.firstIndex(of: "--json") {
    jsonOutput = true
    args.remove(at: jsonIdx)
}

// Parse --app flag
if let appIdx = args.firstIndex(of: "--app"), appIdx + 1 < args.count {
    bundleId = args[appIdx + 1]
    args.removeSubrange(appIdx...appIdx+1)
}

guard let command = args.first else {
    usage()
    exit(0)
}

// Commands that need Accessibility access
let accessibilityCommands: Set<String> = [
    "list", "info", "count", "move", "move-by-title",
    "resize", "resize-by-title",
    "snap", "snap-by-title",
    "move-to-screen", "move-to-screen-by-title",
    "minimize", "minimize-by-title", "restore",
    "save-layout", "restore-layout", "stack", "watch",
    "focus", "focus-by-title", "shake", "shake-by-title",
    "list-open-windows"
]
if accessibilityCommands.contains(command) {
    checkAccessibility()
}

switch command {
case "list":
    listCommand(bundleId: bundleId)
case "info":
    guard args.count >= 2 else {
        fputs("Usage: window-tool info <index>\n", stderr)
        exit(1)
    }
    infoCommand(bundleId: bundleId, index: parseInt(args[1], label: "index"))
case "count":
    countCommand(bundleId: bundleId)
case "move":
    guard args.count >= 4 else {
        fputs("Usage: window-tool move <index> <x> <y> [<width> <height>]\n", stderr)
        exit(1)
    }
    let index = parseInt(args[1], label: "index")
    let x = CGFloat(parseDouble(args[2], label: "x"))
    let y = CGFloat(parseDouble(args[3], label: "y"))
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    if args.count >= 6 {
        width = CGFloat(parseDouble(args[4], label: "width"))
        height = CGFloat(parseDouble(args[5], label: "height"))
    }
    moveCommand(bundleId: bundleId, index: index, x: x, y: y, width: width, height: height)
case "move-by-title":
    guard args.count >= 4 else {
        fputs("Usage: window-tool move-by-title <pattern> <x> <y> [<width> <height>]\n", stderr)
        exit(1)
    }
    let pattern = args[1]
    let x = CGFloat(parseDouble(args[2], label: "x"))
    let y = CGFloat(parseDouble(args[3], label: "y"))
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    if args.count >= 6 {
        width = CGFloat(parseDouble(args[4], label: "width"))
        height = CGFloat(parseDouble(args[5], label: "height"))
    }
    moveByTitleCommand(bundleId: bundleId, titlePattern: pattern, x: x, y: y, width: width, height: height)
case "resize":
    guard args.count >= 4 else {
        fputs("Usage: window-tool resize <index> <width> <height>\n", stderr)
        exit(1)
    }
    let index = parseInt(args[1], label: "index")
    let width = CGFloat(parseDouble(args[2], label: "width"))
    let height = CGFloat(parseDouble(args[3], label: "height"))
    resizeCommand(bundleId: bundleId, index: index, width: width, height: height)
case "resize-by-title":
    guard args.count >= 4 else {
        fputs("Usage: window-tool resize-by-title <pattern> <width> <height>\n", stderr)
        exit(1)
    }
    resizeByTitleCommand(bundleId: bundleId, titlePattern: args[1], width: CGFloat(parseDouble(args[2], label: "width")), height: CGFloat(parseDouble(args[3], label: "height")))
case "snap":
    guard args.count >= 3 else {
        fputs("Usage: window-tool snap <index> <position>\nPositions: \(snapPositions.joined(separator: ", "))\n", stderr)
        exit(1)
    }
    snapCommand(bundleId: bundleId, index: parseInt(args[1], label: "index"), position: args[2])
case "snap-by-title":
    guard args.count >= 3 else {
        fputs("Usage: window-tool snap-by-title <pattern> <position>\nPositions: \(snapPositions.joined(separator: ", "))\n", stderr)
        exit(1)
    }
    snapByTitleCommand(bundleId: bundleId, titlePattern: args[1], position: args[2])
case "move-to-screen":
    guard args.count >= 3 else {
        fputs("Usage: window-tool move-to-screen <index> <screen>\n", stderr)
        exit(1)
    }
    moveToScreenCommand(bundleId: bundleId, windowIndex: parseInt(args[1], label: "index"), screenIndex: parseInt(args[2], label: "screen"))
case "move-to-screen-by-title":
    guard args.count >= 3 else {
        fputs("Usage: window-tool move-to-screen-by-title <pattern> <screen>\n", stderr)
        exit(1)
    }
    moveToScreenByTitleCommand(bundleId: bundleId, titlePattern: args[1], screenIndex: parseInt(args[2], label: "screen"))
case "minimize":
    guard args.count >= 2 else {
        fputs("Usage: window-tool minimize <index>\n", stderr)
        exit(1)
    }
    minimizeCommand(bundleId: bundleId, index: parseInt(args[1], label: "index"))
case "minimize-by-title":
    guard args.count >= 2 else {
        fputs("Usage: window-tool minimize-by-title <pattern>\n", stderr)
        exit(1)
    }
    minimizeByTitleCommand(bundleId: bundleId, titlePattern: args[1])
case "restore":
    restoreCommand(bundleId: bundleId)
case "save-layout":
    guard args.count >= 2 else {
        fputs("Usage: window-tool save-layout <file>\n", stderr)
        exit(1)
    }
    saveLayoutCommand(bundleId: bundleId, filePath: args[1])
case "restore-layout":
    guard args.count >= 2 else {
        fputs("Usage: window-tool restore-layout <file>\n", stderr)
        exit(1)
    }
    restoreLayoutCommand(filePath: args[1])
case "stack":
    let offset = args.count >= 2 ? parseInt(args[1], label: "offset") : 30
    stackCommand(bundleId: bundleId, offsetStep: offset)
case "watch":
    let interval = args.count >= 2 ? parseDouble(args[1], label: "interval") : 1.0
    watchCommand(bundleId: bundleId, interval: interval)
case "focus":
    guard args.count >= 2 else {
        fputs("Usage: window-tool focus <index>\n", stderr)
        exit(1)
    }
    focusCommand(bundleId: bundleId, index: parseInt(args[1], label: "index"))
case "focus-by-title":
    guard args.count >= 2 else {
        fputs("Usage: window-tool focus-by-title <pattern>\n", stderr)
        exit(1)
    }
    focusByTitleCommand(bundleId: bundleId, titlePattern: args[1])
case "shake":
    guard args.count >= 2 else {
        fputs("Usage: window-tool shake <index> [offset] [count] [delay]\n", stderr)
        exit(1)
    }
    let index = parseInt(args[1], label: "index")
    let offset = args.count >= 3 ? parseInt(args[2], label: "offset") : 12
    let count = args.count >= 4 ? parseInt(args[3], label: "count") : 6
    let shakeDelay = args.count >= 5 ? parseDouble(args[4], label: "delay") : 0.04
    shakeCommand(bundleId: bundleId, index: index, offset: offset, count: count, delay: shakeDelay)
case "shake-by-title":
    guard args.count >= 2 else {
        fputs("Usage: window-tool shake-by-title <pattern> [offset] [count] [delay]\n", stderr)
        exit(1)
    }
    let pattern = args[1]
    let offset = args.count >= 3 ? parseInt(args[2], label: "offset") : 12
    let count = args.count >= 4 ? parseInt(args[3], label: "count") : 6
    let shakeDelay = args.count >= 5 ? parseDouble(args[4], label: "delay") : 0.04
    shakeByTitleCommand(bundleId: bundleId, titlePattern: pattern, offset: offset, count: count, delay: shakeDelay)
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
