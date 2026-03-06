import Cocoa

// MARK: - Accessibility Helpers

func getAppElement(bundleId: String) -> AXUIElement? {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    guard let app = apps.first else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

struct WindowInfo {
    let element: AXUIElement
    let id: Int
    let title: String
    let position: CGPoint
    let size: CGSize
}

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

func moveWindow(_ window: AXUIElement, x: CGFloat, y: CGFloat) {
    var point = CGPoint(x: x, y: y)
    if let value = AXValueCreate(.cgPoint, &point) {
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
}

func resizeWindow(_ window: AXUIElement, width: CGFloat, height: CGFloat) {
    var size = CGSize(width: width, height: height)
    if let value = AXValueCreate(.cgSize, &size) {
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}

// MARK: - Screen Helpers

func screensCommand() {
    let mouseLocation = NSEvent.mouseLocation
    for (index, screen) in NSScreen.screens.enumerated() {
        let frame = screen.frame
        let visible = screen.visibleFrame
        // NSScreen uses bottom-left origin, convert to top-left for consistency
        let isMain = (screen == NSScreen.main)
        let containsMouse = frame.contains(mouseLocation)
        var flags: [String] = []
        if isMain { flags.append("main") }
        if containsMouse { flags.append("mouse") }
        let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ","))]"
        print("\(index)\t\(Int(frame.origin.x)),\(Int(frame.origin.y))\t\(Int(frame.width))x\(Int(frame.height))\t\(Int(visible.origin.x)),\(Int(visible.origin.y))\t\(Int(visible.width))x\(Int(visible.height))\(flagStr)")
    }
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
    print("\(Int(frame.origin.x))\t\(Int(topLeftY))\t\(Int(visible.width))\t\(Int(visible.height))")
}

// MARK: - Commands

func listCommand(bundleId: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        fputs("Error: Application not found: \(bundleId)\n", stderr)
        exit(1)
    }
    let windows = getWindows(appElement: app)
    for w in windows {
        print("\(w.id)\t\(Int(w.position.x)),\(Int(w.position.y))\t\(Int(w.size.width))x\(Int(w.size.height))\t\(w.title)")
    }
}

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

func listOpenWindowsCommand() {
    let apps = NSWorkspace.shared.runningApplications
    var entries: [(bundleId: String, name: String)] = []
    var seen = Set<String>()
    for app in apps {
        guard let bundleId = app.bundleIdentifier, !seen.contains(bundleId) else { continue }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        if let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            seen.insert(bundleId)
            entries.append((bundleId: bundleId, name: app.localizedName ?? "Unknown"))
        }
    }
    let sorted = entries.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
    let maxWidth = sorted.map { $0.name.count }.max() ?? 0
    for entry in sorted {
        let padded = entry.name.padding(toLength: maxWidth, withPad: " ", startingAt: 0)
        print("\(padded)  \(entry.bundleId)")
    }
}

func countCommand(bundleId: String) {
    guard let app = getAppElement(bundleId: bundleId) else {
        print("0")
        return
    }
    let windows = getWindows(appElement: app)
    print("\(windows.count)")
}

// MARK: - Main

func usage() {
    let help = """
    Usage: window-tool [--app <bundle-id>] <command> [args...]

    Commands:
      list                                     List all windows with index, position, size, and title
      count                                    Print number of windows
      move <index> <x> <y> [<width> <height>]  Move/resize window by index
      move-by-title <pattern> <x> <y> [<width> <height>]  Move/resize windows matching title
      list-open-windows                        List bundle IDs of apps with open windows
      screens                                  List all displays with bounds
      active-screen                            Print active screen bounds (x, y, width, height)

    Options:
      --app <bundle-id>   Target application (default: com.googlecode.iterm2)

    Examples:
      window-tool list
      window-tool move 0 100 50 1200 900
      window-tool move-by-title "my-notes" 0 0 1400 1000
    """
    print(help)
}

var args = Array(CommandLine.arguments.dropFirst())
var bundleId = "com.googlecode.iterm2"

// Parse --app flag
if let appIdx = args.firstIndex(of: "--app"), appIdx + 1 < args.count {
    bundleId = args[appIdx + 1]
    args.removeSubrange(appIdx...appIdx+1)
}

guard let command = args.first else {
    usage()
    exit(0)
}

switch command {
case "list":
    listCommand(bundleId: bundleId)
case "count":
    countCommand(bundleId: bundleId)
case "move":
    guard args.count >= 4 else {
        fputs("Usage: window-tool move <index> <x> <y> [<width> <height>]\n", stderr)
        exit(1)
    }
    let index = Int(args[1])!
    let x = CGFloat(Double(args[2])!)
    let y = CGFloat(Double(args[3])!)
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    if args.count >= 6 {
        width = CGFloat(Double(args[4])!)
        height = CGFloat(Double(args[5])!)
    }
    moveCommand(bundleId: bundleId, index: index, x: x, y: y, width: width, height: height)
case "move-by-title":
    guard args.count >= 4 else {
        fputs("Usage: window-tool move-by-title <pattern> <x> <y> [<width> <height>]\n", stderr)
        exit(1)
    }
    let pattern = args[1]
    let x = CGFloat(Double(args[2])!)
    let y = CGFloat(Double(args[3])!)
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    if args.count >= 6 {
        width = CGFloat(Double(args[4])!)
        height = CGFloat(Double(args[5])!)
    }
    moveByTitleCommand(bundleId: bundleId, titlePattern: pattern, x: x, y: y, width: width, height: height)
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
