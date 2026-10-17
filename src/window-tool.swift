import AVFoundation
import Cocoa
import Foundation
import ScreenCaptureKit

let VERSION = "0.17.1"

// MARK: - Configuration

struct Config {
    var bundleId: String = ""
    var appExplicit: Bool = false
    var jsonOutput: Bool = false
    var jsonBuffer: [Any] = []
    var jsonChaining: Bool = false
    var chaining: Bool = false
    var lastSelector: WindowSelector?
}

var config = Config()

/// Prints a human-readable status line; under `--json` it goes to stderr so stdout stays valid JSON.
func printStatus(_ message: String) {
    if config.jsonOutput {
        fputs(message + "\n", stderr)
    } else {
        print(message)
    }
}

func printJSON(_ value: Any) {
    if config.jsonChaining {
        config.jsonBuffer.append(value)
    } else {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            fputs("Error: Failed to serialize JSON output\n", stderr)
            exit(1)
        }
        print(str)
    }
}

func flushJSONBuffer() {
    guard !config.jsonBuffer.isEmpty else { return }
    let output = config.jsonBuffer.count == 1 ? config.jsonBuffer[0] : config.jsonBuffer
    guard let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        fputs("Error: Failed to serialize JSON output\n", stderr)
        exit(1)
    }
    print(str)
}

/// Exits without losing JSON results buffered by earlier commands in a chain.
/// Commands throw WindowToolError; this is for callbacks and signal handlers that can't throw.
/// Plain exit() is fine before any command runs.
func flushJSONAndExit(_ status: Int32) -> Never {
    flushJSONBuffer()
    exit(status)
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
    case appRequired
    case missingWindowSelector(command: String)
    case unknownOption(String, command: String)
    case repeatedOption(String, command: String)
    case unexpectedArgument(String, command: String)
    case optionNeedsValue(String)
    case optionTakesNoValue(String, command: String)
    case missingArguments(command: String)
    case unknownCommand(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let id):
            return "Application not found: \(id)"
        case .ambiguousApp(let query, let matches):
            let list = matches.map { "  \($0.name) (\($0.bundleId))" }.joined(separator: "\n")
            return "Multiple apps match '\(query)':\n\(list)\nUse a more specific name or the full bundle ID shown above."
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
        case .appRequired:
            return "--app is required for this command"
        case .missingWindowSelector(let command):
            return "Missing window selector for '\(command)'. Use an index (0, 1, ...), id=<N>, or title=<pattern>.\nRun 'window-tool \(command) --help' for usage."
        case .unknownOption(let option, let command):
            return "Unknown option '\(option)' for '\(command)'. Run 'window-tool \(command) --help'."
        case .repeatedOption(let option, let command):
            return "Option '\(option)' given more than once for '\(command)'. Run 'window-tool \(command) --help'."
        case .unexpectedArgument(let arg, let command):
            return "Unexpected argument '\(arg)' for '\(command)'. Run 'window-tool \(command) --help'."
        case .optionNeedsValue(let option):
            return "Option '\(option)' requires a value"
        case .optionTakesNoValue(let option, let command):
            return "Option '\(option)' takes no value for '\(command)'. Run 'window-tool \(command) --help'."
        case .missingArguments(let command):
            let usage = commandSpec(named: command)?.usageLine ?? "window-tool \(command)"
            return "Missing arguments\nUsage: \(usage)\nRun 'window-tool help \(command)' for details."
        case .unknownCommand(let command):
            let suggestion = closestCommandName(to: command).map { " Did you mean '\($0)'?" } ?? ""
            return "Unknown command '\(command)'.\(suggestion) Run 'window-tool help' for the command list."
        case .operationFailed(let message):
            return message
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

func parsePositiveInt(_ s: String, label: String) throws -> Int {
    guard let v = Int(s), v > 0 else {
        throw WindowToolError.invalidArgument(value: s, label: "\(label) (must be greater than 0)")
    }
    return v
}

func parsePositiveDouble(_ s: String, label: String) throws -> Double {
    guard let v = Double(s), v.isFinite, v > 0 else {
        throw WindowToolError.invalidArgument(value: s, label: "\(label) (must be greater than 0)")
    }
    return v
}

/// Removes the first `--name value` or `--name=value` from `args` and returns the value, or nil when absent.
/// Every command's options go through this so both spellings work everywhere.
/// In the spaced form the next argument is the value even when it starts with `--`.
func takeOption(_ name: String, from args: inout [String]) throws -> String? {
    guard let idx = args.firstIndex(where: { $0 == name || $0.hasPrefix(name + "=") }) else { return nil }
    if args[idx] != name {
        return String(args.remove(at: idx).dropFirst(name.count + 1))
    }
    guard idx + 1 < args.count else {
        throw WindowToolError.optionNeedsValue(name)
    }
    let value = args[idx + 1]
    args.removeSubrange(idx...idx + 1)
    return value
}

/// Removes a boolean `--name` from `args` and returns whether it was there.
func takeFlag(_ name: String, from args: inout [String]) -> Bool {
    guard let idx = args.firstIndex(of: name) else { return false }
    args.remove(at: idx)
    return true
}

/// Throws for the first option left in `args` after a command has taken the ones it knows:
/// a value given to a boolean flag, a repeat of a known option, or one the command does not take.
/// Known options come from the command's spec; negative numbers such as `-100` are values, not options.
func rejectUnknownOptions(_ args: [String], command: String) throws {
    guard let option = args.first(where: { $0.hasPrefix("-") && Double($0) == nil }) else { return }
    let name = String(option.prefix { $0 != "=" })
    // Spec flag names are "--size N" for options with a value and "--push" for boolean flags.
    let specFlags = commandSpec(named: command)?.flags.map(\.name) ?? []
    if option.contains("="), (["--json"] + specFlags).contains(name) {
        throw WindowToolError.optionTakesNoValue(name, command: command)
    }
    let known = ["--app", "--json"] + specFlags.map { String($0.prefix { $0 != " " }) }
    throw known.contains(name)
        ? WindowToolError.repeatedOption(name, command: command)
        : WindowToolError.unknownOption(name, command: command)
}

/// Checks a command's leftover args once its options are taken: rejects any option and any
/// positional beyond the first `max`, and returns the positionals.
@discardableResult
func checkArgs(_ args: [String], command: String, max: Int = 0) throws -> [String] {
    try rejectUnknownOptions(args, command: command)
    if let extra = args.dropFirst(max).first {
        throw WindowToolError.unexpectedArgument(extra, command: command)
    }
    return args
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
    let color = try takeOption("--color", from: &args).map(parseColor) ?? .green
    let count = try takeOption("--count", from: &args).map { try parsePositiveInt($0, label: "count") } ?? 1
    return (color, count)
}

func parseHighlightFlags(_ args: inout [String]) throws -> (color: NSColor, duration: Double) {
    let color = try takeOption("--color", from: &args).map(parseColor) ?? .red
    let duration = try takeOption("--duration", from: &args).map { try parseDouble($0, label: "duration") } ?? 3.0
    return (color, duration)
}

func parseBorderFlags(_ args: inout [String]) throws -> (color: NSColor, width: CGFloat) {
    let color = try takeOption("--color", from: &args).map(parseColor) ?? .blue
    let width = try takeOption("--width", from: &args).map { CGFloat(try parseDouble($0, label: "width")) } ?? 3
    return (color, width)
}

func parseSizeFlag(_ args: inout [String]) throws -> (CGFloat, CGFloat)? {
    guard let value = try takeOption("--size", from: &args) else { return nil }
    if let sep = value.firstIndex(of: ",") ?? value.firstIndex(of: "x") {
        let wStr = String(value[value.startIndex..<sep])
        let hStr = String(value[value.index(after: sep)...])
        let w = CGFloat(try parseDouble(wStr, label: "width"))
        let h = CGFloat(try parseDouble(hStr, label: "height"))
        return (w, h)
    }
    let n = CGFloat(try parseDouble(value, label: "size"))
    return (n, n)
}

func parseSidebarFlags(_ args: inout [String]) throws -> (side: String, fullHeight: Bool, fullWidth: Bool, push: Bool) {
    let side = try takeOption("--side", from: &args) ?? "left"
    let fullHeight = takeFlag("--full-height", from: &args)
    let fullWidth = takeFlag("--full-width", from: &args)
    let push = takeFlag("--push", from: &args)
    return (side, fullHeight, fullWidth, push)
}

func parseTileFlags(_ args: inout [String]) throws -> (gap: Int, cols: Int?, untile: Bool) {
    let gap = try takeOption("--gap", from: &args).map { try parseInt($0, label: "gap") } ?? 10
    let cols = try takeOption("--cols", from: &args).map { try parsePositiveInt($0, label: "cols") }
    let untile = takeFlag("--untile", from: &args)
    return (gap, cols, untile)
}

// MARK: - Sidebar Snapshot

let sidebarSnapshotFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("window-tool-sidebar-snapshot.json")

struct SidebarWindowSnapshot: Codable {
    let bundleId: String
    let windowID: UInt32
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

// MARK: - Tile Snapshot

let tileSnapshotFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("window-tool-tile-snapshot.json")

struct TileWindowSnapshot: Codable {
    let bundleId: String
    let windowID: UInt32
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

// MARK: - Accessibility Helpers

/// Resolves an app identifier to a bundle ID.
/// If the identifier contains a dot, it's treated as an exact bundle ID.
/// Otherwise, an exact case-insensitive app name wins; failing that, it's matched
/// case-insensitively as a substring of app names and bundle IDs of running apps.
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
    let exactMatches = matches.filter { $0.name.lowercased() == query }
    if exactMatches.count == 1 {
        return exactMatches[0].bundleId
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
    /// The zero-based index of the window in the application's window list, or -1 for a child (sheet, dialog) that has no index of its own.
    let id: Int
    /// For a child window, the index of the parent window in the application's window list.
    var parentIndex: Int? = nil
    /// The window's title (may be empty).
    let title: String
    /// The window's top-left screen position.
    let position: CGPoint
    /// The window's dimensions.
    let size: CGSize
    /// The Core Graphics window ID (stable for the lifetime of the window).
    let windowID: CGWindowID?
}

/// Builds a WindowInfo from an AXUIElement window, or returns nil if position/size can't be read.
func makeWindowInfo(element: AXUIElement, id: Int, parentIndex: Int? = nil) -> WindowInfo? {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    let title = titleRef as? String ?? ""

    var posRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
    var position = CGPoint.zero
    if let posRef = posRef {
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
    }

    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
    var size = CGSize.zero
    if let sizeRef = sizeRef {
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
    }

    return WindowInfo(element: element, id: id, parentIndex: parentIndex, title: title, position: position, size: size, windowID: getCGWindowID(element))
}

/// Reads a window's current top-left frame, or returns nil once the window no longer exists.
func currentFrame(of element: AXUIElement) -> CGRect? {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
        return nil
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
    return CGRect(origin: position, size: size)
}

/// Retrieves all windows for the given application element.
/// Each window is returned as a `WindowInfo` with its index, title, position, and size.
func getWindows(appElement: AXUIElement) -> [WindowInfo] {
    var windowsRef: CFTypeRef?
    AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
    guard let windows = windowsRef as? [AXUIElement] else { return [] }

    var result: [WindowInfo] = []
    for (index, window) in windows.enumerated() {
        if let info = makeWindowInfo(element: window, id: index) {
            result.append(info)
        }
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

/// Parses `id=<windowID>` or `title=<pattern>`, or returns nil for any other arg (a bare index or a number argument).
func parseNamedSelector(_ arg: String) throws -> WindowSelector? {
    if arg.hasPrefix("id=") {
        let idStr = String(arg.dropFirst(3))
        guard let id = UInt32(idStr) else {
            throw WindowToolError.invalidArgument(value: arg, label: "window ID")
        }
        return .byWindowID(CGWindowID(id))
    }
    if arg.hasPrefix("title=") {
        let pattern = String(arg.dropFirst(6))
        guard !pattern.isEmpty else {
            throw WindowToolError.invalidArgument(value: arg, label: "title pattern")
        }
        return .byTitle(pattern)
    }
    return nil
}

/// Parses a window selector from a string argument.
/// Supports `id=<windowID>` for CGWindowID, `title=<pattern>` for title match, or a plain integer for index.
func parseWindowSelector(_ arg: String) throws -> WindowSelector {
    try parseNamedSelector(arg) ?? .byIndex(try parseInt(arg, label: "index"))
}

/// Every command that takes one <window> resolves it here, after taking its own options from `args`
/// (the args after the command name). Returns the selector and the positionals after it.
/// `argCounts` lists how many positionals the command accepts after its selector. When chaining, args whose
/// count matches one of those inherit the previous selector, so `+ move 100 200 800 600` moves the inherited
/// window instead of reading 100 as an index. An `id=` or `title=` arg is always a selector.
/// Throws for leftover options and for more positionals than the command accepts.
func resolveSelectorAndArgs(_ args: [String], command: String, argCounts: [Int] = [0]) throws -> (selector: WindowSelector, rest: [String]) {
    try rejectUnknownOptions(args, command: command)
    let named = try args.first.flatMap(parseNamedSelector)
    let selector: WindowSelector
    var rest = args
    if named == nil, config.chaining, let last = config.lastSelector, argCounts.contains(args.count) || args.isEmpty {
        selector = last
    } else if let first = args.first {
        selector = try named ?? parseWindowSelector(first)
        config.lastSelector = selector
        rest.removeFirst()
    } else {
        throw WindowToolError.missingWindowSelector(command: command)
    }
    try checkArgs(rest, command: command, max: argCounts.max() ?? 0)
    return (selector, rest)
}

func requireApp(_ bundleId: String) throws -> AXUIElement {
    guard !bundleId.isEmpty else {
        throw WindowToolError.appRequired
    }
    guard let app = getAppElement(bundleId: bundleId) else {
        throw WindowToolError.appNotFound(bundleId)
    }
    return app
}

/// Resolves a selector to a window. When chaining, pins the inherited selector to the window's
/// CGWindowID so a later command still targets it after an earlier one (e.g. focus) reorders the AX window list.
func resolveWindow(bundleId: String, selector: WindowSelector) throws -> WindowInfo {
    let window = try lookUpWindow(bundleId: bundleId, selector: selector)
    if config.chaining, let windowID = window.windowID {
        config.lastSelector = .byWindowID(windowID)
    }
    return window
}

private func lookUpWindow(bundleId: String, selector: WindowSelector) throws -> WindowInfo {
    // For byWindowID with no --app, go straight to cross-app lookup
    if case .byWindowID(let windowID) = selector, bundleId.isEmpty {
        if let found = findWindowByID(windowID) {
            return found
        }
        throw WindowToolError.noWindowMatchingID(windowID)
    }

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
        if let window = windows.first(where: { $0.windowID == windowID }) {
            return window
        }
        // Fall back: check child windows (sheets, dialogs, modals)
        if let found = findChildWindow(windowID: windowID, in: windows) {
            return found
        }
        // Fall back: find the owning app via CGWindowList and search there
        if let found = findWindowByID(windowID) {
            return found
        }
        throw WindowToolError.noWindowMatchingID(windowID)
    }
}

/// Finds a window by CGWindowID across all running apps using CGWindowList to identify the owner.
func findWindowByID(_ windowID: CGWindowID) -> WindowInfo? {
    guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[CFString: Any]] else {
        return nil
    }
    // Find the owning PID for this window ID
    guard let entry = windowList.first(where: { ($0[kCGWindowNumber] as? CGWindowID) == windowID }),
          let pid = entry[kCGWindowOwnerPID] as? pid_t else {
        return nil
    }
    let appElement = AXUIElementCreateApplication(pid)
    let windows = getWindows(appElement: appElement)
    if let window = windows.first(where: { $0.windowID == windowID }) {
        return window
    }
    // Check child windows of that app
    return findChildWindow(windowID: windowID, in: windows)
}

/// Searches child elements (sheets, dialogs) of the given windows for a matching CGWindowID.
func findChildWindow(windowID: CGWindowID, in windows: [WindowInfo]) -> WindowInfo? {
    for (parentIndex, parent) in windows.enumerated() {
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(parent.element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { continue }
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            // Check windows, sheets, dialogs, and similar roles
            guard role == kAXWindowRole as String || role == kAXSheetRole as String
                  || role == "AXDialog" else { continue }
            if let childID = getCGWindowID(child), childID == windowID {
                return makeWindowInfo(element: child, id: -1, parentIndex: parentIndex)
            }
        }
    }
    return nil
}

func resolveAllWindows(bundleId: String, selector: WindowSelector) throws -> [WindowInfo] {
    if case .byWindowID(let windowID) = selector, bundleId.isEmpty {
        if let found = findWindowByID(windowID) {
            return [found]
        }
        throw WindowToolError.noWindowMatchingID(windowID)
    }

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
        if let window = windows.first(where: { $0.windowID == windowID }) {
            return [window]
        }
        if let found = findChildWindow(windowID: windowID, in: windows) {
            return [found]
        }
        if let found = findWindowByID(windowID) {
            return [found]
        }
        throw WindowToolError.noWindowMatchingID(windowID)
    }
}

// MARK: - Screen Helpers

/// Converts a Cocoa (bottom-left origin) rect to AX global coordinates (top-left origin at the primary display, `NSScreen.screens[0]`).
func cocoaToAX(rect: NSRect) -> NSRect {
    NSRect(x: rect.origin.x, y: NSScreen.screens[0].frame.height - rect.maxY, width: rect.width, height: rect.height)
}

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
            "title": w.title,
            "x": Int(w.position.x), "y": Int(w.position.y),
            "width": Int(w.size.width), "height": Int(w.size.height),
            "minimized": minimized, "fullscreen": fullscreen,
            "focused": focused, "main": main, "modal": modal
        ]
        if let bundleId = bundleId { dict["bundle_id"] = bundleId }
        if let parent = w.parentIndex { dict["parent_index"] = parent } else { dict["index"] = w.id }
        if let wid = w.windowID { dict["window_id"] = Int(wid) }
        if let role = role { dict["role"] = role }
        if let subrole = subrole { dict["subrole"] = subrole }
        if let document = document { dict["document"] = document }
        printJSON(dict)
    } else {
        if let bundleId = bundleId { print("bundle_id:\t\(bundleId)") }
        if let parent = w.parentIndex { print("parent_index:\t\(parent)") } else { print("index:\t\(w.id)") }
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
func activeWindowCommand(idOnly: Bool) throws {
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

    if idOnly {
        if let wid = w.windowID { print(wid) }
    } else {
        printWindowInfo(w, bundleId: bundleId)
    }
}

func shellInitCommand(shell: String) throws {
    let binary = ProcessInfo.processInfo.processName
    switch shell {
    case "zsh":
        print("# Add this to your ~/.zshrc or equivalent file")
        print("# window-tool shell integration")
        print("if [ -z \"$WINDOWID\" ]; then")
        print("  export WINDOWID=\"$(\(binary) active-window --id 2>/dev/null)\"")
        print("fi")
    case "bash":
        print("# Add this to your ~/.bashrc or equivalent file")
        print("# window-tool shell integration")
        print("if [ -z \"$WINDOWID\" ]; then")
        print("  export WINDOWID=\"$(\(binary) active-window --id 2>/dev/null)\"")
        print("fi")
    case "fish":
        print("# Add this to your ~/.config/fish/config.fish or equivalent file")
        print("# window-tool shell integration")
        print("if not set -q WINDOWID")
        print("  set -gx WINDOWID (\(binary) active-window --id 2>/dev/null)")
        print("end")
    default:
        throw WindowToolError.invalidArgument(value: shell, label: "shell (zsh, bash, fish)")
    }
}

func activeScreenCommand() {
    // Return the screen containing the mouse cursor (the "active" screen)
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    // Usable area (excludes menu bar and Dock) in AX global top-left coordinates, ready for window positioning
    let visible = cocoaToAX(rect: screen.visibleFrame)
    if config.jsonOutput {
        printJSON(["x": Int(visible.origin.x), "y": Int(visible.origin.y),
                   "width": Int(visible.width), "height": Int(visible.height)])
    } else {
        print("X\tY\tWIDTH\tHEIGHT")
        print("\(Int(visible.origin.x))\t\(Int(visible.origin.y))\t\(Int(visible.width))\t\(Int(visible.height))")
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

/// Lists windows. When bundleId is provided, lists windows for that app only.
/// When nil, lists all windows across all running apps, sorted by app name.
func listCommand(bundleId: String?) throws {
    struct WindowEntry {
        let app: String
        let bundleId: String
        let index: Int
        let windowID: CGWindowID?
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let title: String
    }

    var entries: [WindowEntry] = []

    if let bundleId = bundleId {
        let appElement = try requireApp(bundleId)
        let appName = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleId }?.localizedName ?? bundleId
        let windows = getWindows(appElement: appElement)
        for w in windows {
            entries.append(WindowEntry(app: appName, bundleId: bundleId, index: w.id,
                                       windowID: w.windowID,
                                       x: Int(w.position.x), y: Int(w.position.y),
                                       width: Int(w.size.width), height: Int(w.size.height),
                                       title: w.title))
        }
    } else {
        let apps = NSWorkspace.shared.runningApplications
        var seen = Set<String>()
        for app in apps {
            guard let bid = app.bundleIdentifier, !seen.contains(bid),
                  app.activationPolicy == .regular else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = getWindows(appElement: appElement)
            if !windows.isEmpty {
                seen.insert(bid)
                let appName = app.localizedName ?? "Unknown"
                for w in windows {
                    entries.append(WindowEntry(app: appName, bundleId: bid, index: w.id,
                                               windowID: w.windowID,
                                               x: Int(w.position.x), y: Int(w.position.y),
                                               width: Int(w.size.width), height: Int(w.size.height),
                                               title: w.title))
                }
            }
        }
        entries.sort(by: { $0.app.lowercased() < $1.app.lowercased() })
    }

    if config.jsonOutput {
        let items = entries.map { e in
            var dict: [String: Any] = [
                "app": e.app, "bundle_id": e.bundleId,
                "index": e.index,
                "x": e.x, "y": e.y,
                "width": e.width, "height": e.height,
                "title": e.title
            ]
            if let wid = e.windowID { dict["window_id"] = Int(wid) }
            return dict
        }
        printJSON(items)
    } else {
        print("APP\tBUNDLE ID\tINDEX\tWID\tPOSITION\tSIZE\tTITLE")
        for e in entries {
            let wid = e.windowID.map { String($0) } ?? "?"
            print("\(e.app)\t\(e.bundleId)\t\(e.index)\t\(wid)\t\(e.x),\(e.y)\t\(e.width)x\(e.height)\t\(e.title)")
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
        printStatus("Moved \(windows.count) window(s) matching '\(pattern)'")
    }
}

/// Brings a window to the front. Activates the application and raises the window.
func focusCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    activateOwner(of: window)
    AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
}

/// Activates the application that owns the window, which may differ from `--app` when an `id=` selector resolved cross-app.
func activateOwner(of window: WindowInfo) {
    var pid: pid_t = 0
    // Best-effort: if the PID can't be read the window is still acted on; it just isn't brought to the front.
    guard AXUIElementGetPid(window.element, &pid) == .success else { return }
    NSRunningApplication(processIdentifier: pid)?.activate()
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
    overlay.level = .normal
    overlay.ignoresMouseEvents = true
    overlay.hasShadow = false

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let view = HighlightView(frame: NSRect(origin: .zero, size: overlayFrame.size))
    view.borderColor = color
    overlay.contentView = view

    if let wid = window.windowID {
        overlay.order(.above, relativeTo: Int(wid))
    } else {
        overlay.orderFrontRegardless()
    }

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

// MARK: - Overlay PID Files

func readPID(at path: String) -> pid_t? {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines))
}

func processName(of pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 256)
    guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
}

/// Sends SIGTERM only when `pid` is a window-tool process, so a stale PID file
/// pointing at a recycled PID cannot kill an unrelated process. Returns whether the signal was sent.
@discardableResult
func terminateOverlay(pid: pid_t) -> Bool {
    guard let name = processName(of: pid), name == processName(of: getpid()) else { return false }
    return kill(pid, SIGTERM) == 0
}

/// Deletes a PID file only if it still holds this process's PID, so a replaced overlay
/// exiting late does not remove the PID file of the overlay that replaced it.
func removePIDFileIfOwned(_ path: String) {
    if readPID(at: path) == getpid() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Dim Overlay

let dimPIDFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("window-tool-dim.pid")

func parseDimFlags(_ args: inout [String]) throws -> (opacity: Double, duration: Double) {
    let opacity = try takeOption("--opacity", from: &args).map { try parseDouble($0, label: "opacity") } ?? 0.5
    let duration = try takeOption("--duration", from: &args).map { try parseDouble($0, label: "duration") } ?? 0
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
    guard let pid = readPID(at: dimPIDFile) else { return }
    terminateOverlay(pid: pid)
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
        removePIDFileIfOwned(dimPIDFile)
        flushJSONAndExit(0)
    }
    signal(SIGTERM, cleanupPID)
    signal(SIGINT, cleanupPID)

    if duration > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            for overlay in overlays { overlay.close() }
            removePIDFileIfOwned(dimPIDFile)
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
    guard let pid = readPID(at: dimPIDFile) else {
        throw WindowToolError.invalidArgument(value: "none", label: "active dim overlay (run 'dim' first)")
    }
    let terminated = terminateOverlay(pid: pid)
    try? FileManager.default.removeItem(atPath: dimPIDFile)
    if !terminated {
        throw WindowToolError.invalidArgument(value: "\(pid)", label: "dim process (not running, or not a window-tool process)")
    }
}

// MARK: - Border Overlay

let borderPidDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("window-tool-borders")

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

/// Returns the PID directory for a window's border, keyed by the bundle ID of the app that owns
/// the window rather than by `--app`, so `id=` selectors and sheets land in the same place.
func borderOwnerDir(for window: WindowInfo) -> String {
    var pid: pid_t = 0
    AXUIElementGetPid(window.element, &pid)
    let owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "\(pid)"
    return "\(borderPidDir)/\(owner)"
}

func borderCommand(bundleId: String, selector: WindowSelector, color: NSColor, width: CGFloat) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    guard let windowID = window.windowID else {
        throw WindowToolError.operationFailed("Could not determine window ID")
    }

    let appBundleDir = borderOwnerDir(for: window)
    try FileManager.default.createDirectory(atPath: appBundleDir, withIntermediateDirectories: true)
    let pidFile = "\(appBundleDir)/\(windowID).pid"

    if let existingPid = readPID(at: pidFile), terminateOverlay(pid: existingPid) {
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
        removePIDFileIfOwned(pidFile)
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
        guard let frame = currentFrame(of: window.element) else {
            timer.invalidate()
            cleanupAndExit()
            return
        }

        let screenHeight = NSScreen.screens[0].frame.height
        let newCocoaY = screenHeight - frame.origin.y - frame.height
        let newFrame = NSRect(x: frame.origin.x, y: newCocoaY,
                              width: frame.width, height: frame.height)
        if overlay.frame != newFrame {
            overlay.setFrame(newFrame, display: false)
            view.frame = NSRect(origin: .zero, size: newFrame.size)
            view.needsDisplay = true
        }
    }

    app.run()
    removePIDFileIfOwned(pidFile)
}

func unborderCommand(bundleId: String, selector: WindowSelector? = nil) throws {
    if let selector = selector {
        guard let window = try? resolveWindow(bundleId: bundleId, selector: selector),
              let windowID = window.windowID else {
            return
        }
        let appDir = borderOwnerDir(for: window)
        let pidFile = "\(appDir)/\(windowID).pid"
        if let pid = readPID(at: pidFile) {
            terminateOverlay(pid: pid)
        }
        try? FileManager.default.removeItem(atPath: pidFile)
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: appDir), remaining.isEmpty {
            try? FileManager.default.removeItem(atPath: appDir)
        }
        return
    }

    // Borders are filed under the owning app (see borderOwnerDir), so --app must name the owner here.
    guard !bundleId.isEmpty else {
        throw WindowToolError.operationFailed("--app is required for this command (or use 'unborder-all' to remove every border)")
    }
    let appDir = "\(borderPidDir)/\(bundleId)"
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: appDir) else {
        return
    }
    for file in files where file.hasSuffix(".pid") {
        let pidFile = "\(appDir)/\(file)"
        if let pid = readPID(at: pidFile) {
            terminateOverlay(pid: pid)
        }
        // Remove unconditionally: terminateOverlay only signals window-tool processes, so a PID file left
        // behind by a dead or foreign process is stale and must not linger.
        try? FileManager.default.removeItem(atPath: pidFile)
    }
    try? FileManager.default.removeItem(atPath: appDir)
}

func unborderAllCommand() {
    guard let bundleDirs = try? FileManager.default.contentsOfDirectory(atPath: borderPidDir) else {
        return
    }
    for bundleDir in bundleDirs {
        try? unborderCommand(bundleId: bundleDir)
    }
}

/// Resizes window(s) without changing position.
func resizeCommand(bundleId: String, selector: WindowSelector, width: CGFloat, height: CGFloat) throws {
    let windows = try resolveAllWindows(bundleId: bundleId, selector: selector)
    for window in windows {
        resizeWindow(window.element, width: width, height: height)
    }
    if case .byTitle(let pattern) = selector {
        printStatus("Resized \(windows.count) window(s) matching '\(pattern)'")
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
    let visible = cocoaToAX(rect: screen.visibleFrame)
    return (x: visible.origin.x, y: visible.origin.y, width: visible.width, height: visible.height)
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
        printStatus("Maximized \(windows.count) window(s) matching '\(pattern)'")
    }
}

/// Centers a window on its current screen, optionally resizing it first.
func centerCommand(bundleId: String, selector: WindowSelector, size: (CGFloat, CGFloat)?) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let bounds = screenBoundsForWindow(window)
    let w: CGFloat
    let h: CGFloat
    if let (sw, sh) = size {
        w = sw
        h = sh
        resizeWindow(window.element, width: w, height: h)
    } else {
        w = window.size.width
        h = window.size.height
    }
    moveWindow(window.element, x: bounds.x + (bounds.width - w) / 2, y: bounds.y + (bounds.height - h) / 2)
}

/// Pins a window to the left or right edge of its screen as a sidebar.
func sidebarCommand(bundleId: String, selector: WindowSelector, side: String, fullHeight: Bool, fullWidth: Bool, push: Bool) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let bounds = screenBoundsForWindow(window)
    let w = fullWidth ? bounds.width : window.size.width
    let h = fullHeight ? bounds.height : window.size.height

    let sidebarX: CGFloat
    let sidebarY: CGFloat
    switch side {
    case "left":
        sidebarX = bounds.x
        sidebarY = bounds.y
    case "right":
        sidebarX = bounds.x + bounds.width - w
        sidebarY = bounds.y
    case "top":
        sidebarX = bounds.x
        sidebarY = bounds.y
    case "bottom":
        sidebarX = bounds.x
        sidebarY = bounds.y + bounds.height - h
    default:
        throw WindowToolError.invalidArgument(value: side, label: "side (left, right, top, bottom)")
    }
    moveWindow(window.element, x: sidebarX, y: sidebarY)
    if fullHeight || fullWidth {
        resizeWindow(window.element, width: w, height: h)
    }

    if push {
        // The sidebar's final rectangle
        let sidebarRect = CGRect(x: sidebarX, y: sidebarY, width: w, height: h)
        let sidebarWindowID = window.windowID

        var snapshots: [SidebarWindowSnapshot] = []
        let apps = NSWorkspace.shared.runningApplications
        var seen = Set<String>()
        for app in apps {
            guard let bid = app.bundleIdentifier, !seen.contains(bid),
                  app.activationPolicy == .regular else { continue }
            seen.insert(bid)
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = getWindows(appElement: appElement)
            for win in windows {
                // Skip the sidebar window itself
                if let wid = win.windowID, let sid = sidebarWindowID, wid == sid { continue }
                // Skip windows with zero size (minimized, etc.)
                if win.size.width <= 0 || win.size.height <= 0 { continue }
                guard let wid = win.windowID else { continue }

                // Check if window center is on the same screen
                let winBounds = screenBoundsForWindow(win)
                guard winBounds.x == bounds.x && winBounds.y == bounds.y &&
                      winBounds.width == bounds.width && winBounds.height == bounds.height else { continue }

                // Snapshot the window's current position
                snapshots.append(SidebarWindowSnapshot(
                    bundleId: bid,
                    windowID: wid,
                    x: Int(win.position.x),
                    y: Int(win.position.y),
                    width: Int(win.size.width),
                    height: Int(win.size.height)
                ))

                // Check overlap with sidebar
                let winRect = CGRect(x: win.position.x, y: win.position.y,
                                     width: win.size.width, height: win.size.height)
                if winRect.intersects(sidebarRect) {
                    var newX = win.position.x
                    var newY = win.position.y
                    var newW = win.size.width
                    var newH = win.size.height

                    switch side {
                    case "left":
                        newX = sidebarRect.maxX
                        let screenRight = bounds.x + bounds.width
                        if newX + newW > screenRight { newW = screenRight - newX }
                    case "right":
                        let newRight = sidebarRect.minX
                        newX = newRight - newW
                        if newX < bounds.x { newX = bounds.x; newW = newRight - bounds.x }
                    case "top":
                        newY = sidebarRect.maxY
                        let screenBottom = bounds.y + bounds.height
                        if newY + newH > screenBottom { newH = screenBottom - newY }
                    case "bottom":
                        let newBottom = sidebarRect.minY
                        newY = newBottom - newH
                        if newY < bounds.y { newY = bounds.y; newH = newBottom - bounds.y }
                    default:
                        break
                    }

                    if newW > 0 && newH > 0 {
                        moveWindow(win.element, x: newX, y: newY)
                        resizeWindow(win.element, width: newW, height: newH)
                    }
                }
            }
        }

        // Save snapshot
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshots)
        try data.write(to: URL(fileURLWithPath: sidebarSnapshotFile), options: .atomic)
    }
}

/// Restores windows to their pre-sidebar positions from the snapshot file.
func sidebarUnpushCommand() throws {
    guard FileManager.default.fileExists(atPath: sidebarSnapshotFile) else {
        throw WindowToolError.operationFailed("No sidebar snapshot found at \(sidebarSnapshotFile)")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: sidebarSnapshotFile))
    let snapshots = try JSONDecoder().decode([SidebarWindowSnapshot].self, from: data)

    var restored = 0
    for snap in snapshots {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == snap.bundleId }
        guard let app = apps.first else { continue }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement: appElement)
        guard let win = windows.first(where: { $0.windowID == snap.windowID }) else { continue }
        moveWindow(win.element, x: CGFloat(snap.x), y: CGFloat(snap.y))
        resizeWindow(win.element, width: CGFloat(snap.width), height: CGFloat(snap.height))
        restored += 1
    }

    try FileManager.default.removeItem(atPath: sidebarSnapshotFile)
    printStatus("Restored \(restored) window(s)")
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
    let visible = cocoaToAX(rect: targetScreen.visibleFrame)
    moveWindow(window.element, x: visible.origin.x, y: visible.origin.y)
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
    printStatus("Restored \(restored) window(s)")
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
            let contentRect = filter.contentRect
            let scale = filter.pointPixelScale
            config.width = Int(contentRect.width * CGFloat(scale))
            config.height = Int(contentRect.height * CGFloat(scale))
            capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            captureError = error
        }
        semaphore.signal()
    }

    semaphore.wait()

    if let error = captureError { throw error }
    guard let image = capturedImage else {
        throw WindowToolError.operationFailed("Failed to capture window image")
    }
    return image
}

func parsePreviewFlags(_ args: inout [String]) throws -> String? {
    try takeOption("--output", from: &args)
}

func previewCommand(bundleId: String, selector: WindowSelector, outputPath: String?) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    guard let windowID = window.windowID else {
        throw WindowToolError.operationFailed("Cannot capture window — no window ID available")
    }

    let image = try captureWindowImage(windowID: windowID)

    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw WindowToolError.operationFailed("Failed to encode PNG")
    }

    let resolvedPath: String
    if let path = outputPath {
        resolvedPath = (path as NSString).expandingTildeInPath
    } else {
        resolvedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("window-tool-preview-\(windowID).png")
    }
    let url = URL(fileURLWithPath: resolvedPath)
    try pngData.write(to: url, options: .atomic)

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

func parseRecordFlags(_ args: inout [String]) throws -> (output: String, fps: Int, duration: Double?, countdown: Bool, border: Bool) {
    guard let output = try takeOption("--output", from: &args) else {
        throw WindowToolError.invalidArgument(value: "--output", label: "flag (required, specify an output file path)")
    }
    let fps = try takeOption("--fps", from: &args).map { try parsePositiveInt($0, label: "fps") } ?? 30
    let duration = try takeOption("--duration", from: &args).map { try parseDouble($0, label: "duration") }
    let countdown = !takeFlag("--no-countdown", from: &args)
    let border = !takeFlag("--no-border", from: &args)
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
    private(set) var framesWritten = 0
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
            if adaptor.append(pixelBuffer, withPresentationTime: time) {
                lock.lock()
                framesWritten += 1
                lock.unlock()
            }
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

// Retained to prevent deallocation which would cancel the signal handlers.
var recordingSignalSources: [Any] = []

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
                flushJSONAndExit(1)
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
                    if assetWriter.status != .completed || delegate.framesWritten == 0 {
                        let reason = delegate.framesWritten == 0
                            ? "no frames were captured (is the window minimized or off-screen? restore it and retry)"
                            : (assetWriter.error?.localizedDescription ?? "unknown error")
                        try? FileManager.default.removeItem(at: outputURL)
                        fputs("Error: Recording failed: \(reason)\n", stderr)
                        flushJSONAndExit(1)
                    }
                    fputs("Recording saved to \(outputURL.path)\n", stderr)
                    if config.jsonOutput {
                        printJSON(["path": outputURL.path, "window_id": Int(windowID), "width": width, "height": height])
                    } else {
                        print(outputURL.path)
                    }
                    flushJSONAndExit(0)
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

            // Keep signal sources alive — they cancel on dealloc
            recordingSignalSources = [intSource, termSource]

            if let duration = duration {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    stopRecording()
                }
            }

        } catch let error as NSError where error.domain == "com.apple.ScreenCaptureKit.ErrorDomain" {
            fputs("Error: Screen Recording permission is not granted.\nGrant access in System Settings > Privacy & Security > Screen Recording.\n", stderr)
            flushJSONAndExit(1)
        } catch {
            setupError = error
            semaphore.signal()
        }
    }

    DispatchQueue.global().async {
        semaphore.wait()
        if let error = setupError {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            flushJSONAndExit(1)
        }
    }
}

func recordCommand(bundleId: String, selector: WindowSelector, output: String, fps: Int, duration: Double?, countdown: Bool, border: Bool) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    guard let windowID = window.windowID else {
        throw WindowToolError.operationFailed("Cannot record window — no window ID available")
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

// MARK: - Identify Command

func identifyCommand(bundleId: String?, duration: Double, color: NSColor) throws {
    struct IdentifyWindow {
        let windowID: CGWindowID
        let position: CGPoint
        let size: CGSize
    }

    // Build z-ordered list of on-screen window rects (front-to-back) so we can
    // skip windows whose center is occluded by a window in front of them.
    struct OnScreenRect {
        let windowID: CGWindowID
        let frame: CGRect
    }
    let onScreenWindows: [OnScreenRect] = {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        var rects: [OnScreenRect] = []
        for entry in windowList {
            guard let id = entry[kCGWindowNumber] as? CGWindowID,
                  let layer = entry[kCGWindowLayer] as? Int, layer == 0,
                  let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 0, h > 0 else { continue }
            rects.append(OnScreenRect(windowID: id, frame: CGRect(x: x, y: y, width: w, height: h)))
        }
        return rects
    }()

    // Returns true if the center of the window is not covered by any window in front of it.
    func isCenterVisible(windowID: CGWindowID, center: CGPoint) -> Bool {
        for entry in onScreenWindows {
            if entry.windowID == windowID { return true }  // reached our window, nothing above covers it
            if entry.frame.contains(center) { return false }  // a window in front covers the center
        }
        return false  // window not in the on-screen list at all
    }

    var windows: [IdentifyWindow] = []

    if let bundleId = bundleId {
        let appElement = try requireApp(bundleId)
        for w in getWindows(appElement: appElement) {
            guard let wid = w.windowID else { continue }
            let center = CGPoint(x: w.position.x + w.size.width / 2, y: w.position.y + w.size.height / 2)
            guard isCenterVisible(windowID: wid, center: center) else { continue }
            windows.append(IdentifyWindow(windowID: wid, position: w.position, size: w.size))
        }
    } else {
        let apps = NSWorkspace.shared.runningApplications
        var seen = Set<String>()
        for app in apps {
            guard let bid = app.bundleIdentifier, !seen.contains(bid),
                  app.activationPolicy == .regular else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let appWindows = getWindows(appElement: appElement)
            if !appWindows.isEmpty {
                seen.insert(bid)
                for w in appWindows {
                    guard let wid = w.windowID else { continue }
                    let center = CGPoint(x: w.position.x + w.size.width / 2, y: w.position.y + w.size.height / 2)
                    guard isCenterVisible(windowID: wid, center: center) else { continue }
                    windows.append(IdentifyWindow(windowID: wid, position: w.position, size: w.size))
                }
            }
        }
    }

    guard !windows.isEmpty else {
        fputs("No windows found\n", stderr)
        return
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let mainScreenHeight = NSScreen.screens[0].frame.height
    var overlays: [NSWindow] = []

    for w in windows {
        let labelText = "id=\(w.windowID)"

        let label = NSTextField(labelWithString: labelText)
        label.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 24
        let boxWidth = label.frame.width + padding * 2
        let boxHeight = label.frame.height + padding * 2

        let cocoaY = mainScreenHeight - w.position.y - w.size.height
        let boxX = w.position.x + (w.size.width - boxWidth) / 2
        let boxY = cocoaY + (w.size.height - boxHeight) / 2

        let overlay = NSWindow(
            contentRect: NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = color.withAlphaComponent(0.85)
        overlay.level = .normal
        overlay.ignoresMouseEvents = true
        overlay.hasShadow = true

        label.frame = NSRect(x: padding, y: padding, width: label.frame.width, height: label.frame.height)
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: boxWidth, height: boxHeight)))
        container.addSubview(label)
        overlay.contentView = container

        overlay.orderFrontRegardless()
        overlays.append(overlay)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        for overlay in overlays { overlay.close() }
        app.stop(nil)
        let dummyEvent = NSEvent.otherEvent(with: .applicationDefined,
                                            location: .zero, modifierFlags: [],
                                            timestamp: 0, windowNumber: 0,
                                            context: nil, subtype: 0,
                                            data1: 0, data2: 0)!
        app.postEvent(dummyEvent, atStart: true)
    }
    app.run()
}

// MARK: - Pick Command

/// Waits for the user to click on a window, then prints its CGWindowID.
func pickCommand() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    fputs("Click on a window to get its ID...\n", stderr)

    // Only normal, floating and modal-panel windows are real app windows; every other layer
    // (menu bar, Dock, status items) is skipped because no command can resolve those IDs.
    let pickableLayers = Set([CGWindowLevelKey.normalWindow, .floatingWindow, .modalPanelWindow]
        .map { Int(CGWindowLevelForKey($0)) })

    NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
        // NSEvent.mouseLocation gives screen coordinates (bottom-left origin)
        let screenPoint = NSEvent.mouseLocation
        // CGWindowList uses top-left origin
        let mainScreenHeight = NSScreen.screens[0].frame.height
        let cgPoint = CGPoint(x: screenPoint.x, y: mainScreenHeight - screenPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            fputs("Error: Could not get window list\n", stderr)
            flushJSONAndExit(1)
        }

        // Walk front-to-back, find first window containing the click
        for entry in windowList {
            guard let layer = entry[kCGWindowLayer] as? Int, pickableLayers.contains(layer),
                  let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 0, h > 0,
                  let windowID = entry[kCGWindowNumber] as? CGWindowID else { continue }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.contains(cgPoint) {
                if config.jsonOutput {
                    printJSON(["window_id": Int(windowID)])
                } else {
                    print("id=\(windowID)")
                }
                flushJSONAndExit(0)
            }
        }

        fputs("No pickable window at click location (menu bar, Dock and status items are skipped)\n", stderr)
        flushJSONAndExit(1)
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
    printStatus("Saved \(windows.count) window(s) to \(filePath)")
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
    printStatus("Restored \(restored)/\(layout.windows.count) window(s) for \(layout.bundleId)")
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
    printStatus("Stacked \(windows.count) window(s)")
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

    signal(SIGINT) { _ in flushJSONAndExit(0) }

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

    // Reversed so the first column's app is activated last and ends frontmost
    for window in selected.reversed() {
        activateOwner(of: window)
    }

    for (i, window) in selected.enumerated() {
        let x = bounds.x + CGFloat(i) * (colWidth + CGFloat(gap))
        moveWindow(window.element, x: x, y: bounds.y)
        resizeWindow(window.element, width: colWidth, height: bounds.height)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }
    printStatus("Arranged \(selected.count) window(s) in columns")
}

func calculateGrid(windowCount: Int, colsOverride: Int?) -> (rows: Int, cols: Int) {
    let n = windowCount
    if let override = colsOverride {
        let cols = min(override, n)
        let rows = Int(ceil(Double(n) / Double(cols)))
        return (rows, cols)
    }
    let cols = Int(ceil(sqrt(Double(n))))
    let rows = Int(ceil(Double(n) / Double(cols)))
    return (rows, cols)
}

func tileCommand(bundleId: String, selectors: [WindowSelector]?, gap: Int, colsOverride: Int?) throws {
    let app = try requireApp(bundleId)
    var windows: [WindowInfo]
    if let selectors = selectors, !selectors.isEmpty {
        windows = []
        for selector in selectors {
            windows.append(try resolveWindow(bundleId: bundleId, selector: selector))
        }
    } else {
        windows = getWindows(appElement: app)
    }

    guard !windows.isEmpty else {
        throw WindowToolError.operationFailed("No windows found")
    }

    let bounds = screenBoundsForWindow(windows[0])

    // Snapshot all windows before moving
    var snapshots: [TileWindowSnapshot] = []
    for win in windows {
        guard let wid = win.windowID else { continue }
        snapshots.append(TileWindowSnapshot(
            bundleId: bundleId,
            windowID: wid,
            x: Int(win.position.x),
            y: Int(win.position.y),
            width: Int(win.size.width),
            height: Int(win.size.height)
        ))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshots)
    try data.write(to: URL(fileURLWithPath: tileSnapshotFile), options: .atomic)

    let (rows, cols) = calculateGrid(windowCount: windows.count, colsOverride: colsOverride)
    let cellWidth = (bounds.width - CGFloat(gap) * CGFloat(cols - 1)) / CGFloat(cols)
    let cellHeight = (bounds.height - CGFloat(gap) * CGFloat(rows - 1)) / CGFloat(rows)

    for (i, window) in windows.enumerated() {
        let row = i / cols
        let col = i % cols
        let x = bounds.x + CGFloat(col) * (cellWidth + CGFloat(gap))
        let y = bounds.y + CGFloat(row) * (cellHeight + CGFloat(gap))
        resizeWindow(window.element, width: cellWidth, height: cellHeight)
        moveWindow(window.element, x: x, y: y)
    }
    printStatus("Tiled \(windows.count) window(s) in \(rows)x\(cols) grid")
}

/// Restores windows to their pre-tile positions from the snapshot file.
func untileCommand() throws {
    guard FileManager.default.fileExists(atPath: tileSnapshotFile) else {
        throw WindowToolError.operationFailed("No tile snapshot found at \(tileSnapshotFile)")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: tileSnapshotFile))
    let snapshots = try JSONDecoder().decode([TileWindowSnapshot].self, from: data)

    var restored = 0
    for snap in snapshots {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == snap.bundleId }
        guard let app = apps.first else { continue }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement: appElement)
        guard let win = windows.first(where: { $0.windowID == snap.windowID }) else { continue }
        moveWindow(win.element, x: CGFloat(snap.x), y: CGFloat(snap.y))
        resizeWindow(win.element, width: CGFloat(snap.width), height: CGFloat(snap.height))
        restored += 1
    }

    try FileManager.default.removeItem(atPath: tileSnapshotFile)
    printStatus("Restored \(restored) window(s)")
}

/// Prints the number of windows for the given application. Throws if `--app` is missing or the app is not found.
func countCommand(bundleId: String) throws {
    let app = try requireApp(bundleId)
    let windows = getWindows(appElement: app)
    if config.jsonOutput { printJSON(["count": windows.count]) } else { print("\(windows.count)") }
}

// MARK: - Command Metadata

enum CommandGroup: String, CaseIterable {
    case query = "Query"
    case moveSize = "Move/size"
    case layout = "Layout"
    case overlays = "Overlays"
    case capture = "Capture"
    case meta = "Meta"
}

/// How a command uses --app. `optional` commands take a <window>, and `id=` selectors find the app themselves.
enum AppUsage {
    case required, optional, none
}

/// One command's help. `synopsis` lists positional arguments only; " [options]" is added when `flags` is non-empty.
/// `mutates` is true when the command changes a window's position, size, state or focus.
/// `needsAccessibility` and `resolvesOwnApp` drive `runCommand`'s up-front checks; `commands --json` reports them.
struct CommandSpec {
    let name: String
    let group: CommandGroup
    let app: AppUsage
    let mutates: Bool
    var synopsis = ""
    let summary: String
    var arguments: [(name: String, description: String)] = []
    var flags: [(name: String, description: String)] = []
    var needsAccessibility = true
    /// True when the command resolves `--app` itself (it is optional and absent means "all apps").
    var resolvesOwnApp = false

    var usageLine: String {
        let appPrefix: String
        switch app {
        case .required: appPrefix = "--app <name-or-id> "
        case .optional: appPrefix = "[--app <name-or-id>] "
        case .none: appPrefix = ""
        }
        let parts = [name, synopsis, flags.isEmpty ? "" : "[options]"].filter { !$0.isEmpty }
        return "window-tool \(appPrefix)\(parts.joined(separator: " "))"
    }

    var json: [String: Any] {
        let appValue: String
        switch app {
        case .required: appValue = "required"
        case .optional: appValue = "optional"
        case .none: appValue = "none"
        }
        let describe = { (rows: [(name: String, description: String)]) in rows.map { ["name": $0.name, "description": $0.description] } }
        return ["name": name, "group": group.rawValue, "app": appValue, "mutates": mutates,
                "accessibility": needsAccessibility, "synopsis": synopsis, "summary": summary,
                "arguments": describe(arguments), "flags": describe(flags)]
    }

    var help: String {
        var lines = ["Usage: \(usageLine)", "", summary + "."]
        for (title, rows) in [("Arguments", arguments), ("Options", flags)] where !rows.isEmpty {
            lines += ["", "\(title):"] + helpRows(rows)
        }
        if synopsis.contains("<window>") {
            lines += ["", "<window> is an index from 'list', id=<window-id>, or title=<pattern>."]
            if app == .optional {
                lines.append("Index and title= selectors need --app; id= finds the window's app itself.")
            }
        }
        lines += ["", "Run 'window-tool help' for global options, chaining and all commands."]
        return lines.joined(separator: "\n")
    }
}

/// Formats name/description pairs as an indented two-column list.
func helpRows(_ rows: [(name: String, description: String)], width: Int? = nil) -> [String] {
    let width = width ?? rows.map(\.name.count).max() ?? 0
    return rows.map { "  " + $0.name.padding(toLength: width + 2, withPad: " ", startingAt: 0) + $0.description }
}

/// Every command, in the order the top-level help lists them within each group.
/// Each `runCommand` case needs a spec here (a command without one skips the Accessibility check), or `help <command>` and its usage errors cannot find it.
let commandSpecs: [CommandSpec] = [
    CommandSpec(name: "list", group: .query, app: .optional, mutates: false,
                summary: "List windows (all apps, or one app with --app)", resolvesOwnApp: true),
    CommandSpec(name: "info", group: .query, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Show detailed info for a window"),
    CommandSpec(name: "count", group: .query, app: .required, mutates: false,
                summary: "Print the number of windows for --app"),
    CommandSpec(name: "active-window", group: .query, app: .none, mutates: false,
                summary: "Print info about the frontmost app's primary window",
                flags: [("--id", "Print only the window ID")]),
    CommandSpec(name: "active-screen", group: .query, app: .none, mutates: false,
                summary: "Print the active screen's usable bounds (x, y, width, height)", needsAccessibility: false),
    CommandSpec(name: "screens", group: .query, app: .none, mutates: false,
                summary: "List all displays with bounds", needsAccessibility: false),
    CommandSpec(name: "pick", group: .query, app: .none, mutates: false,
                summary: "Click a window to print its ID (blocks until you click)", needsAccessibility: false),
    CommandSpec(name: "watch", group: .query, app: .required, mutates: false, synopsis: "[interval]",
                summary: "Print window changes for --app until interrupted",
                arguments: [("[interval]", "Poll interval in seconds, greater than 0 (default: 1.0)")]),

    CommandSpec(name: "snap", group: .moveSize, app: .optional, mutates: true, synopsis: "<window> <position>",
                summary: "Snap a window to a screen region",
                arguments: [("<position>", SnapPosition.allNames)]),
    CommandSpec(name: "move", group: .moveSize, app: .optional, mutates: true, synopsis: "<window> <x> <y> [<width> <height>]",
                summary: "Move a window, optionally resizing it",
                arguments: [("<x> <y>", "Top-left corner in screen points"),
                            ("<width> <height>", "New size in points")]),
    CommandSpec(name: "resize", group: .moveSize, app: .optional, mutates: true, synopsis: "<window> <width> <height>",
                summary: "Resize a window"),
    CommandSpec(name: "center", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Center a window on its screen",
                flags: [("--size N", "Resize to N x N points first"),
                        ("--size W,H", "Resize to W x H points first (also --size WxH)")]),
    CommandSpec(name: "maximize", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Maximize a window to fill its screen"),
    CommandSpec(name: "move-to-screen", group: .moveSize, app: .optional, mutates: true, synopsis: "<window> <screen>",
                summary: "Move a window to another display",
                arguments: [("<screen>", "Display index from 'screens'")]),
    CommandSpec(name: "focus", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Bring a window to the front"),
    CommandSpec(name: "minimize", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Minimize a window"),
    CommandSpec(name: "restore", group: .moveSize, app: .required, mutates: true,
                summary: "Restore all minimized windows for --app"),
    CommandSpec(name: "fullscreen", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Enter macOS fullscreen"),
    CommandSpec(name: "unfullscreen", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Exit macOS fullscreen"),

    CommandSpec(name: "tile", group: .layout, app: .required, mutates: true, synopsis: "[<window>...]",
                summary: "Tile windows in a grid (all windows for --app when none are given)",
                flags: [("--gap N", "Gap between windows in pixels (default: 10)"),
                        ("--cols N", "Force a number of columns, greater than 0"),
                        ("--untile", "Restore windows to their pre-tile positions (no --app needed)")]),
    CommandSpec(name: "columnize", group: .layout, app: .optional, mutates: true, synopsis: "<window> <window> [<window>...]",
                summary: "Arrange windows side by side in columns",
                flags: [("--gap N", "Gap between columns in pixels (default: 10)")]),
    CommandSpec(name: "stack", group: .layout, app: .required, mutates: true, synopsis: "[offset]",
                summary: "Cascade the windows for --app",
                arguments: [("[offset]", "Pixels between each window (default: 30)")]),
    CommandSpec(name: "sidebar", group: .layout, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Pin a window to an edge of its screen",
                flags: [("--side left|right|top|bottom", "Edge to pin to (default: left)"),
                        ("--full-height", "Fill the screen height"),
                        ("--full-width", "Fill the screen width"),
                        ("--push", "Push overlapping windows away from the sidebar"),
                        ("--unpush", "Restore windows moved by --push (takes no <window>)")]),
    CommandSpec(name: "save-layout", group: .layout, app: .required, mutates: false, synopsis: "<file>",
                summary: "Save the window layout for --app to a JSON file"),
    CommandSpec(name: "restore-layout", group: .layout, app: .none, mutates: true, synopsis: "<file>",
                summary: "Restore a window layout from a JSON file (the file names the app)"),

    CommandSpec(name: "highlight", group: .overlays, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Briefly highlight a window (blocks until it dismisses)",
                flags: [("--color <color>", "Overlay color (default: red)"),
                        ("--duration <seconds>", "How long to show it (default: 3)")]),
    CommandSpec(name: "flash", group: .overlays, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Flash a colored overlay on a window",
                flags: [("--color <color>", "Overlay color (default: green)"),
                        ("--count N", "Number of flashes, greater than 0 (default: 1)")]),
    CommandSpec(name: "border", group: .overlays, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Add a persistent border that tracks a window",
                flags: [("--color <color>", "Border color (default: blue)"),
                        ("--width N", "Border width in points (default: 3)")]),
    CommandSpec(name: "unborder", group: .overlays, app: .optional, mutates: false, synopsis: "[<window>]",
                summary: "Remove borders for --app, or for one window",
                arguments: [("[<window>]", "Window whose border to remove; without it, --app is required")]),
    CommandSpec(name: "unborder-all", group: .overlays, app: .none, mutates: false,
                summary: "Remove all active borders", needsAccessibility: false),
    CommandSpec(name: "dim", group: .overlays, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Dim everything except a window",
                flags: [("--opacity <value>", "Overlay opacity, 0.0-1.0 (default: 0.5)"),
                        ("--duration <seconds>", "Dismiss after this long; 0 stays until 'undim' (default: 0)")]),
    CommandSpec(name: "undim", group: .overlays, app: .none, mutates: false,
                summary: "Remove the active dim overlay", needsAccessibility: false),
    CommandSpec(name: "identify", group: .overlays, app: .optional, mutates: false,
                summary: "Label visible windows with their IDs (blocks until they dismiss)",
                flags: [("--color <color>", "Label color (default: magenta)"),
                        ("--duration <seconds>", "How long to show the labels (default: 3)")], resolvesOwnApp: true),
    CommandSpec(name: "shake", group: .overlays, app: .optional, mutates: true, synopsis: "<window> [offset] [count] [delay]",
                summary: "Shake a window to draw attention to it",
                arguments: [("[offset]", "Shake distance in pixels (default: 12)"),
                            ("[count]", "Number of shakes, greater than 0 (default: 6)"),
                            ("[delay]", "Seconds between movements (default: 0.04)")]),

    CommandSpec(name: "preview", group: .capture, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Save a screenshot of a window as PNG",
                flags: [("--output <path>", "Output file (default: $TMPDIR/window-tool-preview-<id>.png)")]),
    CommandSpec(name: "record", group: .capture, app: .optional, mutates: false, synopsis: "<window> --output <path>",
                summary: "Record video of a window",
                flags: [("--output <path>", "Output file (.mov or .mp4), required"),
                        ("--fps N", "Frames per second, greater than 0 (default: 30)"),
                        ("--duration <seconds>", "Stop after this long (default: until Ctrl-C)"),
                        ("--no-countdown", "Skip the 3-second countdown"),
                        ("--no-border", "Don't show a border while recording")]),

    CommandSpec(name: "help", group: .meta, app: .none, mutates: false, synopsis: "[<command>]",
                summary: "Show all commands, or one command's arguments and options", needsAccessibility: false),
    CommandSpec(name: "commands", group: .meta, app: .none, mutates: false,
                summary: "List every command; with --json, its arguments, options, --app usage and whether it mutates",
                needsAccessibility: false),
    CommandSpec(name: "shell-init", group: .meta, app: .none, mutates: false, synopsis: "<shell>",
                summary: "Print a shell integration snippet",
                arguments: [("<shell>", "zsh, bash or fish")], needsAccessibility: false),
]

/// Prints the command list: names and summaries, or with --json the full table plus the valid values for enum-like arguments.
func commandsCommand() {
    if config.jsonOutput {
        printJSON(["version": VERSION, "commands": commandSpecs.map(\.json),
                   "enums": ["snapPositions": SnapPosition.allCases.map(\.rawValue), "colors": validColors, "shells": ["zsh", "bash", "fish"]]] as [String: Any])
    } else {
        print(helpRows(commandSpecs.map { (name: $0.name, description: $0.summary) }).joined(separator: "\n"))
    }
}

func commandSpec(named name: String) -> CommandSpec? {
    commandSpecs.first { $0.name == name }
}

func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var previous = Array(0...b.count)
    for i in a.indices.map({ $0 + 1 }) {
        var current = [i]
        for j in b.indices.map({ $0 + 1 }) {
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)))
        }
        previous = current
    }
    return previous[b.count]
}

/// The command name closest to `input`, or nil when nothing is within a couple of typos (one for short names, two for longer ones).
func closestCommandName(to input: String) -> String? {
    let input = input.lowercased()
    let ranked = commandSpecs.map { (name: $0.name, distance: editDistance(input, $0.name)) }.min { $0.distance < $1.distance }
    guard let best = ranked, best.distance <= max(1, min(2, best.name.count / 3)) else { return nil }
    return best.name
}

// MARK: - Main

/// Prints the top-level help: every command grouped as in `commandSpecs`, then selectors, options and chaining.
func usage() {
    let entries = commandSpecs.map { spec in
        (group: spec.group, name: [spec.name, spec.synopsis].filter { !$0.isEmpty }.joined(separator: " "), description: spec.summary)
    }
    let width = entries.map(\.name.count).max() ?? 0
    var lines = [
        "Usage: window-tool [--app <name-or-id>] [--json] <command> [args...]",
        "       window-tool help <command>        Show one command's arguments and options",
    ]
    for group in CommandGroup.allCases {
        let rows = entries.filter { $0.group == group }.map { (name: $0.name, description: $0.description) }
        lines += ["", "\(group.rawValue):"] + helpRows(rows, width: width)
    }
    let help = """

    Window selectors:
      <window> can be:
        0, 1, 2...          Index from 'list' output (needs --app)
        id=<window_id>      CGWindowID (e.g., id=1341); finds the window's app itself
        title=<pattern>     Substring match on window title (needs --app)
      Use 'list' to see available indices and window IDs. Prefer id= in scripts.

    Snap positions:
      \(SnapPosition.allNames)

    Colors:
      \(validColors.joined(separator: ", "))

    Options:
      --app <name-or-id>  Target application by name or bundle ID
      --json              Output in JSON format
      --help, -h          Show help; after a command, show that command's help
      --version, -v       Print version and exit
      Options that take a value accept --flag value or --flag=value.
      Unknown options and extra arguments are errors; the command does not run.

    Output:
      Results go to stdout and errors to stderr. With --json, status messages
      also go to stderr so stdout holds only JSON.

    Command chaining:
      Use + to run multiple commands in sequence, sharing --app and --json flags.
      Subsequent commands inherit the window selector from the previous command.
      Bare numbers that fit a command's arguments are arguments (+ shake 20);
      use id= or title= to name another window:
      window-tool --app Safari snap 0 center + focus + highlight --color red
      window-tool --app iTerm info 0 + info 1
      window-tool focus id=2457 + highlight + dim id=2789

    Examples:
      window-tool list
      window-tool --app Safari list
      window-tool --app iTerm columnize 0 1 2
      window-tool --app Safari move 0 100 50 1200 900
      window-tool focus id=1341
      window-tool --app Notes move title="my-notes" 0 0 1400 1000
      window-tool --app Safari focus 0 + highlight 0
      window-tool help snap
    """
    print((lines + [help]).joined(separator: "\n"))
}

var args = Array(CommandLine.arguments.dropFirst())

// Parse --json flag
if let jsonIdx = args.firstIndex(of: "--json") {
    config.jsonOutput = true
    args.remove(at: jsonIdx)
}

// Parse --app flag
do {
    if let app = try takeOption("--app", from: &args) {
        guard !app.isEmpty else { throw WindowToolError.appRequired }
        config.bundleId = app
        config.appExplicit = true
    }
} catch {
    fputs("Error: --app requires an app name or bundle identifier\n", stderr)
    exit(1)
}

guard !args.isEmpty else {
    usage()
    exit(0)
}

if args.first == "--version" || args.first == "-v" {
    print("window-tool \(VERSION)")
    exit(0)
}

// Split args on "+" to support chaining multiple commands
func splitCommands(_ args: [String]) -> [[String]] {
    var commands: [[String]] = []
    var current: [String] = []
    for arg in args {
        if arg == "+" {
            if !current.isEmpty { commands.append(current) }
            current = []
        } else {
            current.append(arg)
        }
    }
    if !current.isEmpty { commands.append(current) }
    return commands
}

let splitGroups = splitCommands(args)
// `<command> --help` (or -h) anywhere in a chain shows that command's help and runs nothing.
let helpTarget = splitGroups.first { $0.dropFirst().contains { $0 == "--help" || $0 == "-h" } }
let commandGroups = helpTarget.map { [["help", $0[0]]] } ?? splitGroups

/// Runs one command. Each case takes its options from `rest` first, then checks what is left with
/// `resolveSelectorAndArgs` (commands with one <window>), `rejectUnknownOptions` (commands taking a list of
/// windows) or `checkArgs` (the others), so unknown options and extra arguments fail before anything runs.
func runCommand(_ args: [String]) throws {
    guard let spec = commandSpec(named: args[0] == "--help" || args[0] == "-h" ? "help" : args[0]) else {
        throw WindowToolError.unknownCommand(args[0])
    }
    let command = spec.name
    var rest = Array(args.dropFirst())

    if spec.needsAccessibility {
        try checkAccessibility()
    }

    let appIndependent = spec.app == .none || spec.resolvesOwnApp
    if !appIndependent && !config.bundleId.isEmpty {
        config.bundleId = try resolveAppIdentifier(config.bundleId)
    }

    switch command {
    case "list":
        try checkArgs(rest, command: command)
        let resolvedBundleId: String? = config.appExplicit ? try resolveAppIdentifier(config.bundleId) : nil
        try listCommand(bundleId: resolvedBundleId)
    case "info":
        try infoCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "columnize":
        let gap = try takeOption("--gap", from: &rest).map { try parseInt($0, label: "gap") } ?? 10
        try rejectUnknownOptions(rest, command: command)
        guard rest.count >= 2 else {
            throw WindowToolError.missingArguments(command: "columnize")
        }
        let selectors = try rest.map { try parseWindowSelector($0) }
        try columnizeCommand(bundleId: config.bundleId, selectors: selectors, gap: gap)
    case "tile":
        let tileFlags = try parseTileFlags(&rest)
        if tileFlags.untile {
            try checkArgs(rest, command: command)
            try untileCommand()
        } else {
            try rejectUnknownOptions(rest, command: command)
            let selectors: [WindowSelector]? = rest.isEmpty ? nil : try rest.map { try parseWindowSelector($0) }
            try tileCommand(bundleId: config.bundleId, selectors: selectors, gap: tileFlags.gap, colsOverride: tileFlags.cols)
        }
    case "center":
        let size = try parseSizeFlag(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try centerCommand(bundleId: config.bundleId, selector: selector, size: size)
    case "count":
        try checkArgs(rest, command: command)
        try countCommand(bundleId: config.bundleId)
    case "move":
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: [2, 4])
        guard values.count == 2 || values.count == 4 else {
            throw WindowToolError.missingArguments(command: "move")
        }
        let x = CGFloat(try parseDouble(values[0], label: "x"))
        let y = CGFloat(try parseDouble(values[1], label: "y"))
        var width: CGFloat? = nil
        var height: CGFloat? = nil
        if values.count == 4 {
            width = CGFloat(try parseDouble(values[2], label: "width"))
            height = CGFloat(try parseDouble(values[3], label: "height"))
        }
        try moveCommand(bundleId: config.bundleId, selector: selector, x: x, y: y, width: width, height: height)
    case "resize":
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: [2])
        guard values.count == 2 else {
            throw WindowToolError.missingArguments(command: "resize")
        }
        let width = CGFloat(try parseDouble(values[0], label: "width"))
        let height = CGFloat(try parseDouble(values[1], label: "height"))
        try resizeCommand(bundleId: config.bundleId, selector: selector, width: width, height: height)
    case "snap":
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: [1])
        guard let posStr = values.first else {
            throw WindowToolError.missingArguments(command: "snap")
        }
        guard let position = SnapPosition(rawValue: posStr) else {
            throw WindowToolError.invalidArgument(value: posStr, label: "position (valid: \(SnapPosition.allNames))")
        }
        try snapCommand(bundleId: config.bundleId, selector: selector, position: position)
    case "sidebar":
        let (side, fullHeight, fullWidth, push) = try parseSidebarFlags(&rest)
        if takeFlag("--unpush", from: &rest) {
            try checkArgs(rest, command: command)
            try sidebarUnpushCommand()
        } else {
            let selector = try resolveSelectorAndArgs(rest, command: command).selector
            try sidebarCommand(bundleId: config.bundleId, selector: selector, side: side, fullHeight: fullHeight, fullWidth: fullWidth, push: push)
        }
    case "move-to-screen":
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: [1])
        guard let screenArg = values.first else {
            throw WindowToolError.missingArguments(command: "move-to-screen")
        }
        try moveToScreenCommand(bundleId: config.bundleId, selector: selector, screenIndex: try parseInt(screenArg, label: "screen"))
    case "maximize":
        try maximizeCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "minimize":
        try minimizeCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "restore":
        try checkArgs(rest, command: command)
        try restoreCommand(bundleId: config.bundleId)
    case "save-layout":
        guard let filePath = try checkArgs(rest, command: command, max: 1).first else {
            throw WindowToolError.missingArguments(command: "save-layout")
        }
        try saveLayoutCommand(bundleId: config.bundleId, filePath: filePath)
    case "restore-layout":
        guard let filePath = try checkArgs(rest, command: command, max: 1).first else {
            throw WindowToolError.missingArguments(command: "restore-layout")
        }
        try restoreLayoutCommand(filePath: filePath)
    case "stack":
        let offset = try checkArgs(rest, command: command, max: 1).first.map { try parseInt($0, label: "offset") } ?? 30
        try stackCommand(bundleId: config.bundleId, offsetStep: offset)
    case "watch":
        let interval = try checkArgs(rest, command: command, max: 1).first.map { try parsePositiveDouble($0, label: "interval") } ?? 1.0
        try watchCommand(bundleId: config.bundleId, interval: interval)
    case "focus":
        try focusCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "fullscreen":
        try fullscreenCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "unfullscreen":
        try unfullscreenCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "shake":
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: [0, 1, 2, 3])
        let offset = values.count >= 1 ? try parseInt(values[0], label: "offset") : 12
        let count = values.count >= 2 ? try parsePositiveInt(values[1], label: "count") : 6
        let delay = values.count >= 3 ? try parseDouble(values[2], label: "delay") : 0.04
        try shakeCommand(bundleId: config.bundleId, selector: selector, offset: offset, count: count, delay: delay)
    case "flash":
        let flags = try parseFlashFlags(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try flashCommand(bundleId: config.bundleId, selector: selector, color: flags.color, count: flags.count)
    case "highlight":
        let hlFlags = try parseHighlightFlags(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try highlightCommand(bundleId: config.bundleId, selector: selector, color: hlFlags.color, duration: hlFlags.duration)
    case "pick":
        try checkArgs(rest, command: command)
        pickCommand()
    case "identify":
        let identifyDuration = try takeOption("--duration", from: &rest).map { try parseDouble($0, label: "duration") } ?? 3.0
        let identifyColor = try takeOption("--color", from: &rest).map(parseColor) ?? .magenta
        try checkArgs(rest, command: command)
        let resolvedBundleId: String? = config.appExplicit ? try resolveAppIdentifier(config.bundleId) : nil
        try identifyCommand(bundleId: resolvedBundleId, duration: identifyDuration, color: identifyColor)
    case "border":
        let borderFlags = try parseBorderFlags(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try borderCommand(bundleId: config.bundleId, selector: selector, color: borderFlags.color, width: borderFlags.width)
    case "unborder":
        if !rest.isEmpty || (config.chaining && config.lastSelector != nil) {
            try unborderCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
        } else {
            try unborderCommand(bundleId: config.bundleId)
        }
    case "unborder-all":
        try checkArgs(rest, command: command)
        unborderAllCommand()
    case "dim":
        let dimFlags = try parseDimFlags(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try dimCommand(bundleId: config.bundleId, selector: selector, opacity: dimFlags.opacity, duration: dimFlags.duration)
    case "undim":
        try checkArgs(rest, command: command)
        try undimCommand()
    case "preview":
        let outputPath = try parsePreviewFlags(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try previewCommand(bundleId: config.bundleId, selector: selector, outputPath: outputPath)
    case "record":
        let recordFlags = try parseRecordFlags(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try recordCommand(bundleId: config.bundleId, selector: selector, output: recordFlags.output, fps: recordFlags.fps, duration: recordFlags.duration, countdown: recordFlags.countdown, border: recordFlags.border)
    case "screens":
        try checkArgs(rest, command: command)
        screensCommand()
    case "active-screen":
        try checkArgs(rest, command: command)
        activeScreenCommand()
    case "active-window":
        let idOnly = takeFlag("--id", from: &rest)
        try checkArgs(rest, command: command)
        try activeWindowCommand(idOnly: idOnly)
    case "shell-init":
        guard let shell = try checkArgs(rest, command: command, max: 1).first else {
            throw WindowToolError.missingArguments(command: "shell-init")
        }
        try shellInitCommand(shell: shell)
    case "commands":
        try checkArgs(rest, command: command)
        commandsCommand()
    case "help":
        guard let name = try checkArgs(rest, command: command, max: 1).first else {
            usage()
            break
        }
        guard let target = commandSpec(named: name) else {
            throw WindowToolError.unknownCommand(name)
        }
        print(target.help)
    default:
        // A spec with no case here: add the case when adding a command to `commandSpecs`.
        throw WindowToolError.unknownCommand(command)
    }
}

config.chaining = commandGroups.count > 1
config.jsonChaining = config.jsonOutput && config.chaining

do {
    for (index, group) in commandGroups.enumerated() {
        do {
            try runCommand(group)
        } catch {
            if commandGroups.count > 1 {
                fputs("Error in command \(index + 1) (\(group[0])): \(error.localizedDescription)\n", stderr)
            } else {
                fputs("Error: \(error.localizedDescription)\n", stderr)
            }
            flushJSONAndExit(1)
        }
    }
    flushJSONBuffer()
}
