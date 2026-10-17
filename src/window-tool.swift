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
    var keepGoing: Bool = false
    var firstMatch: Bool = false
    var jsonChaining: Bool = false
    var chaining: Bool = false
    var lastSelector: WindowSelector?
    /// Under `--json` in a chain: the entries for the `{"results", "failed_at"}` envelope, the 1-based
    /// number of the first failed command, and the running command with the JSON it has printed so far.
    var chainResults: [[String: Any]] = []
    var chainFailedAt: Int?
    var runningCommand: String?
    var commandOutput: [Any] = []
}

var config = Config()

/// Prints a human-readable status line. Under `--json` it is skipped: the command's JSON result replaces it.
func printStatus(_ message: String) {
    if !config.jsonOutput { print(message) }
}

func writeJSON(_ value: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        fputs("Error: Failed to serialize JSON output\n", stderr)
        exit(1)
    }
    print(str)
}

/// Prints a command's JSON result; in a chain it is held for the command's entry in the results envelope.
func printJSON(_ value: Any) {
    if config.jsonChaining {
        config.commandOutput.append(value)
    } else {
        writeJSON(value)
    }
}

/// Under `--json` in a chain, closes the running command's entry: `data` is what it printed (null for
/// nothing, an array when it printed more than once), or `error` is the given error object.
func recordChainResult(error: [String: Any]? = nil) {
    guard config.jsonChaining, let command = config.runningCommand else { return }
    var entry: [String: Any] = ["command": command, "ok": error == nil]
    if let error {
        entry["error"] = error
        config.chainFailedAt = config.chainFailedAt ?? config.chainResults.count + 1
    } else {
        let output = config.commandOutput
        entry["data"] = output.isEmpty ? NSNull() : output.count == 1 ? output[0] : output
    }
    config.chainResults.append(entry)
    config.runningCommand = nil
    config.commandOutput = []
}

/// Under `--json` in a chain, prints the `{"results", "failed_at"}` envelope. A command that exits
/// from a callback (pick, record, watch) has its entry closed here.
func flushJSONBuffer() {
    guard config.jsonChaining else { return }
    recordChainResult()
    writeJSON(["results": config.chainResults, "failed_at": config.chainFailedAt ?? NSNull()] as [String: Any])
}

/// Exits after printing a chain's results envelope, so no buffered JSON is lost.
/// Commands throw WindowToolError; callbacks and signal handlers that can't throw report errors
/// with exitWithError and successes with this.
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
    case ambiguousWindowTitle(pattern: String, matches: [(index: Int, windowID: CGWindowID?, title: String)])
    case noWindowMatchingID(CGWindowID)
    case screenIndexOutOfRange(index: Int, count: Int)
    case noWindows
    case noPickableWindow
    /// A window answered the close with a sheet (such as "Do you want to save changes?") instead of closing.
    case unsavedChanges(windows: [(windowID: CGWindowID?, title: String)])
    /// `wait` ran out of time; `what` finishes the sentence "Timed out after Ns waiting for ...".
    case timedOut(what: String, seconds: Double)
    case accessibilityNotEnabled
    case screenRecordingNotEnabled
    case invalidValue(name: String, expected: String, got: String)
    case unknownChoice(kind: String, value: String, choices: [String])
    case optionRequired(option: String, command: String, placeholder: String)
    case nothingToUndo(command: String)
    case fileNotFound(String)
    /// `hint` replaces the default pointer to id= for commands where a window ID does not help.
    case appRequired(hint: String? = nil)
    case missingWindowSelector(command: String)
    case unknownOption(String, command: String)
    case repeatedOption(String, command: String)
    case unexpectedArgument(String, command: String)
    /// `command` is nil when thrown by takeOption; the top-level catch fills it in.
    case optionNeedsValue(String, command: String?)
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
        case .ambiguousWindowTitle(let pattern, let matches):
            let list = matches.map { "  \($0.windowID.map { "id=\($0)" } ?? "no id")  [\($0.index)]  \($0.title)" }.joined(separator: "\n")
            return "\(matches.count) windows match title '\(pattern)':\n\(list)\nUse id=<N> or an index, or pass --first to use the first match."
        case .noWindowMatchingID(let windowID):
            return "No window found with ID \(windowID)"
        case .screenIndexOutOfRange(let index, let count):
            return "Screen index \(index) out of range (0..\(count - 1))"
        case .noWindows:
            return "No windows found"
        case .noPickableWindow:
            return "No pickable window at click location (menu bar, Dock and status items are skipped)"
        case .unsavedChanges(let windows):
            return "Not closed, the window is asking about unsaved changes: \(windows.map { "'\($0.title)'" }.joined(separator: ", ")). Answer the prompt in the app, then run close again."
        case .timedOut(let what, let seconds):
            return "Timed out after \(formatSeconds(seconds)) waiting for \(what)"
        case .accessibilityNotEnabled:
            return "Accessibility access is not enabled.\nGrant access in System Settings > Privacy & Security > Accessibility.\nAdd this terminal app or the window-tool binary."
        case .screenRecordingNotEnabled:
            return "Screen Recording permission is not granted.\nGrant access in System Settings > Privacy & Security > Screen Recording."
        case .invalidValue(let name, let expected, let got):
            return "\(name) must be \(expected), got '\(got)'"
        case .unknownChoice(let kind, let value, let choices):
            return "Unknown \(kind) '\(value)'. Choose one of: \(choices.joined(separator: ", "))"
        case .optionRequired(let option, let command, let placeholder):
            return "\(command) requires \(option) \(placeholder)"
        case .nothingToUndo(let command):
            return "Nothing to undo. Run '\(command)' first."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .appRequired(let hint):
            return "--app <name> is required for this command. " + (hint ?? "When selecting a window, id=<N> works without it; run 'window-tool list' to see window IDs.")
        case .missingWindowSelector(let command):
            return "Missing window selector for '\(command)'. Use an index (0, 1, ...), id=<N>, or title=<pattern>.\nRun 'window-tool \(command) --help' for usage."
        case .unknownOption(let option, let command):
            return "Unknown option '\(option)' for '\(command)'. Run 'window-tool \(command) --help'."
        case .repeatedOption(let option, let command):
            return "Option '\(option)' given more than once for '\(command)'. Run 'window-tool \(command) --help'."
        case .unexpectedArgument(let arg, let command):
            return "Unexpected argument '\(arg)' for '\(command)'. Run 'window-tool \(command) --help'."
        case .optionNeedsValue(let option, let command):
            return "Option '\(option)' requires a value" + (command.map { ". Run 'window-tool \($0) --help'." } ?? "")
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

    /// Stable identifier for scripts, printed as `error.code` under `--json`.
    var code: String {
        switch self {
        case .appNotFound: return "app_not_found"
        case .ambiguousApp: return "ambiguous_app"
        case .windowIndexOutOfRange: return "window_index_out_of_range"
        case .noWindowMatchingTitle: return "no_window_matching_title"
        case .ambiguousWindowTitle: return "ambiguous_window_title"
        case .noWindowMatchingID: return "no_window_matching_id"
        case .screenIndexOutOfRange: return "screen_index_out_of_range"
        case .noWindows: return "no_windows"
        case .noPickableWindow: return "no_pickable_window"
        case .unsavedChanges: return "unsaved_changes"
        case .timedOut: return "timeout"
        case .accessibilityNotEnabled: return "accessibility_not_enabled"
        case .screenRecordingNotEnabled: return "screen_recording_not_enabled"
        case .invalidValue: return "invalid_value"
        case .unknownChoice: return "unknown_choice"
        case .optionRequired: return "option_required"
        case .nothingToUndo: return "nothing_to_undo"
        case .fileNotFound: return "file_not_found"
        case .appRequired: return "app_required"
        case .missingWindowSelector: return "missing_window_selector"
        case .unknownOption: return "unknown_option"
        case .repeatedOption: return "repeated_option"
        case .unexpectedArgument: return "unexpected_argument"
        case .optionNeedsValue: return "option_needs_value"
        case .optionTakesNoValue: return "option_takes_no_value"
        case .missingArguments: return "missing_arguments"
        case .unknownCommand: return "unknown_command"
        case .operationFailed: return "operation_failed"
        }
    }

    /// The values behind the message, printed as `error.details` under `--json`.
    var details: [String: Any] {
        switch self {
        case .appNotFound(let app):
            return ["app": app]
        case .ambiguousApp(let query, let matches):
            return ["query": query, "matches": matches.map { ["name": $0.name, "bundle_id": $0.bundleId] }]
        case .windowIndexOutOfRange(let index, let count), .screenIndexOutOfRange(let index, let count):
            return ["index": index, "count": count]
        case .noWindowMatchingTitle(let pattern):
            return ["title": pattern]
        case .ambiguousWindowTitle(let pattern, let matches):
            return ["title": pattern, "matches": matches.map { ["index": $0.index, "window_id": $0.windowID.map { Int($0) } ?? NSNull(), "title": $0.title] as [String: Any] }]
        case .noWindowMatchingID(let windowID):
            return ["window_id": Int(windowID)]
        case .invalidValue(let name, let expected, let got):
            return ["name": name, "expected": expected, "got": got]
        case .unknownChoice(let kind, let value, let choices):
            return ["kind": kind, "value": value, "choices": choices]
        case .optionRequired(let option, let command, _):
            return ["option": option, "command": command]
        case .nothingToUndo(let command), .missingWindowSelector(let command), .missingArguments(let command):
            return ["command": command]
        case .fileNotFound(let path):
            return ["path": path]
        case .timedOut(let what, let seconds):
            return ["waiting_for": what, "timeout": seconds]
        case .unsavedChanges(let windows):
            return ["windows": windows.map { ["window_id": $0.windowID.map { Int($0) } ?? NSNull(), "title": $0.title] as [String: Any] }]
        case .unknownOption(let option, let command), .repeatedOption(let option, let command), .optionTakesNoValue(let option, let command):
            return ["option": option, "command": command]
        case .unexpectedArgument(let argument, let command):
            return ["argument": argument, "command": command]
        case .optionNeedsValue(let option, let command):
            return ["option": option, "command": command ?? NSNull()]
        case .unknownCommand(let command):
            return ["command": command, "suggestion": closestCommandName(to: command) ?? NSNull()]
        case .noWindows, .noPickableWindow, .accessibilityNotEnabled, .screenRecordingNotEnabled, .appRequired, .operationFailed:
            return [:]
        }
    }

    /// 2 usage, 3 app not found, 4 window not found, 5 permission denied, 6 unsaved changes blocked a close, 7 a wait timed out, 1 anything else.
    var exitCode: Int32 {
        switch self {
        case .invalidValue, .unknownChoice, .optionRequired, .appRequired, .missingWindowSelector, .unknownOption,
             .repeatedOption, .unexpectedArgument, .optionNeedsValue, .optionTakesNoValue, .missingArguments, .unknownCommand,
             .screenIndexOutOfRange:
            return 2
        case .appNotFound, .ambiguousApp:
            return 3
        case .windowIndexOutOfRange, .noWindowMatchingTitle, .ambiguousWindowTitle, .noWindowMatchingID, .noWindows, .noPickableWindow:
            return 4
        case .accessibilityNotEnabled, .screenRecordingNotEnabled:
            return 5
        case .unsavedChanges:
            return 6
        case .timedOut:
            return 7
        case .nothingToUndo, .fileNotFound, .operationFailed:
            return 1
        }
    }
}

/// Reports an error without exiting. The message goes to stderr; under `--json` the
/// `{"code", "message", "details"}` object goes to stdout as `{"error": …}`, or in a chain becomes
/// the running command's entry in the results envelope. Errors from system frameworks report as `operation_failed`.
@discardableResult
func reportError(_ error: Error, prefix: String = "Error") -> WindowToolError {
    let toolError = error as? WindowToolError ?? .operationFailed(error.localizedDescription)
    let message = toolError.localizedDescription
    fputs("\(prefix): \(message)\n", stderr)
    if config.jsonOutput {
        let object: [String: Any] = ["code": toolError.code, "message": message, "details": toolError.details]
        if config.jsonChaining {
            recordChainResult(error: object)
        } else {
            printJSON(["error": object])
        }
    }
    return toolError
}

/// Reports an error and exits with its code.
func exitWithError(_ error: Error, prefix: String = "Error") -> Never {
    flushJSONAndExit(reportError(error, prefix: prefix).exitCode)
}

// MARK: - Argument Parsing Helpers

func parseInt(_ s: String, label: String) throws -> Int {
    guard let v = Int(s) else {
        throw WindowToolError.invalidValue(name: label, expected: "a whole number", got: s)
    }
    return v
}

func parseDouble(_ s: String, label: String) throws -> Double {
    guard let v = Double(s) else {
        throw WindowToolError.invalidValue(name: label, expected: "a number", got: s)
    }
    return v
}

func parsePositiveInt(_ s: String, label: String) throws -> Int {
    guard let v = Int(s), v > 0 else {
        throw WindowToolError.invalidValue(name: label, expected: "a whole number greater than 0", got: s)
    }
    return v
}

func parsePositiveDouble(_ s: String, label: String) throws -> Double {
    guard let v = Double(s), v.isFinite, v > 0 else {
        throw WindowToolError.invalidValue(name: label, expected: "a number greater than 0", got: s)
    }
    return v
}

/// A duration for messages: whole seconds without a decimal point (`10s`), otherwise as given (`0.5s`).
func formatSeconds(_ seconds: Double) -> String {
    seconds == seconds.rounded() ? "\(Int(seconds))s" : "\(seconds)s"
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
        throw WindowToolError.optionNeedsValue(name, command: nil)
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
        throw WindowToolError.unknownChoice(kind: "color", value: name, choices: validColors)
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

/// Rounds an AX position or size to the nearest integer (AX reports fractional values on Retina displays). Capture pixel sizes in preview/record deliberately keep truncating.
func roundedInt(_ v: CGFloat) -> Int { Int(v.rounded()) }

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

/// A window the running command moved, resized or otherwise changed, with the frame it asked for, kept so
/// `reportAffectedWindows` can re-read it afterwards. Windows with a minimum size, fullscreen windows and
/// windows on other Spaces can ignore a request without the set call failing.
struct AffectedWindow {
    let element: AXUIElement
    var position: CGPoint?
    var size: CGSize?
    var failures: [String] = []
}

var affectedWindows: [AffectedWindow] = []

/// Warnings a command adds on its own (for example saved windows `restore-layout` could not match); reported with the frame warnings.
var commandWarnings: [String] = []

/// Records that the running command changed `window`. moveWindow/resizeWindow call it with what they requested;
/// commands that change a window another way (focus, minimize, fullscreen) call it themselves.
func recordAffectedWindow(_ window: AXUIElement, position: CGPoint? = nil, size: CGSize? = nil, failure: String? = nil) {
    let index = affectedWindows.firstIndex { CFEqual($0.element, window) } ?? {
        affectedWindows.append(AffectedWindow(element: window))
        return affectedWindows.count - 1
    }()
    affectedWindows[index].position = position ?? affectedWindows[index].position
    affectedWindows[index].size = size ?? affectedWindows[index].size
    if let failure { affectedWindows[index].failures.append(failure) }
}

/// Moves a window to the specified screen coordinates.
func moveWindow(_ window: AXUIElement, x: CGFloat, y: CGFloat) {
    var point = CGPoint(x: x, y: y)
    guard let value = AXValueCreate(.cgPoint, &point) else { return }
    let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    recordAffectedWindow(window, position: point, failure: result == .success ? nil : "could not set position (AXError \(result.rawValue))")
}

/// Resizes a window to the specified width and height.
func resizeWindow(_ window: AXUIElement, width: CGFloat, height: CGFloat) {
    var size = CGSize(width: width, height: height)
    guard let value = AXValueCreate(.cgSize, &size) else { return }
    let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    recordAffectedWindow(window, size: size, failure: result == .success ? nil : "could not set size (AXError \(result.rawValue))")
}

/// Runs after each command. Re-reads every window it changed and prints `Warning: ...` to stderr for each set
/// call that failed or left the frame more than 2 points from the request. With `asJSON` (a mutating command
/// under `--json`) it prints the command's result: `{"windows": [...], "warnings": [...]}`, each window in the
/// `info` schema after the change plus `requested` when a frame was asked for. Clears the recorded windows.
func reportAffectedWindows(asJSON: Bool) {
    defer { affectedWindows = []; commandWarnings = [] }
    var warnings = commandWarnings
    var windows: [[String: Any]] = []
    for affected in affectedWindows {
        let label = axString(affected.element, kAXTitleAttribute as String).map { "'\($0)'" } ?? "window"
        var problems = affected.failures
        if problems.isEmpty, let frame = currentFrame(of: affected.element) {
            if let p = affected.position, abs(frame.origin.x - p.x) > 2 || abs(frame.origin.y - p.y) > 2 {
                problems.append("position requested \(roundedInt(p.x)),\(roundedInt(p.y)) but is \(roundedInt(frame.origin.x)),\(roundedInt(frame.origin.y))")
            }
            if let s = affected.size, abs(frame.size.width - s.width) > 2 || abs(frame.size.height - s.height) > 2 {
                problems.append("size requested \(roundedInt(s.width))x\(roundedInt(s.height)) but is \(roundedInt(frame.size.width))x\(roundedInt(frame.size.height))")
            }
        }
        warnings += problems.map { "\(label): \($0)" }
        guard asJSON, var window = affectedWindowJSON(affected.element) else { continue }
        var requested: [String: Int] = [:]
        if let p = affected.position { requested["x"] = roundedInt(p.x); requested["y"] = roundedInt(p.y) }
        if let s = affected.size { requested["width"] = roundedInt(s.width); requested["height"] = roundedInt(s.height) }
        if !requested.isEmpty { window["requested"] = requested }
        windows.append(window)
    }
    warnings.forEach { fputs("Warning: \($0)\n", stderr) }
    if asJSON { printJSON(["windows": windows, "warnings": warnings] as [String: Any]) }
}

/// A changed window in the `info` schema with its owner's `bundle_id`, or nil once it no longer exists.
/// `index` is its place in the owner's window list, left out when the window is not in that list.
func affectedWindowJSON(_ element: AXUIElement) -> [String: Any]? {
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, currentFrame(of: element) != nil else { return nil }
    let index = getWindows(appElement: AXUIElementCreateApplication(pid)).firstIndex { CFEqual($0.element, element) }
    guard let info = makeWindowInfo(element: element, id: index ?? -1) else { return nil }
    var json = windowInfoJSON(info, bundleId: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    if index == nil { json["index"] = nil }
    return json
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
            throw WindowToolError.invalidValue(name: "id=<N>", expected: "a non-negative whole number", got: idStr)
        }
        return .byWindowID(CGWindowID(id))
    }
    if arg.hasPrefix("title=") {
        let pattern = String(arg.dropFirst(6))
        guard !pattern.isEmpty else {
            throw WindowToolError.invalidValue(name: "title=", expected: "a non-empty pattern (e.g. title=Inbox)", got: "")
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
        throw WindowToolError.appRequired()
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

/// `title=` matches a case-insensitive substring of the window title.
private func titleMatches(_ window: WindowInfo, _ pattern: String) -> Bool {
    window.title.range(of: pattern, options: .caseInsensitive) != nil
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
        let matching = windows.filter { titleMatches($0, pattern) }
        guard let window = matching.first else {
            throw WindowToolError.noWindowMatchingTitle(pattern)
        }
        if matching.count > 1 && !config.firstMatch {
            throw WindowToolError.ambiguousWindowTitle(pattern: pattern, matches: matching.map { ($0.id, $0.windowID, $0.title) })
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
        let matching = windows.filter { titleMatches($0, pattern) }
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

/// The display UUID, which survives reconnects and reboots unlike the index. Nil if macOS has none for the display.
func displayUUID(_ screen: NSScreen) -> String? {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
          let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
}

/// The values a screen argument accepts besides a display index.
let screenNames = ["primary", "external", "left", "right", "next", "prev"]

/// Resolves a screen argument (a display index or one of `screenNames`) to a display index.
/// `frames` are the displays in global top-left coordinates, indexed as in `screens`; `current` is the display
/// that `left`, `right`, `next` and `prev` are relative to. `next` and `prev` wrap around in index order.
func resolveScreenIndex(_ value: String, frames: [CGRect], current: Int) throws -> Int {
    if let index = Int(value) {
        guard frames.indices.contains(index) else {
            throw WindowToolError.screenIndexOutOfRange(index: index, count: frames.count)
        }
        return index
    }
    func nearest(_ direction: CGFloat) throws -> Int {
        let candidates = frames.indices.filter { (frames[$0].midX - frames[current].midX) * direction > 0 }
        guard let best = candidates.min(by: { abs(frames[$0].midX - frames[current].midX) < abs(frames[$1].midX - frames[current].midX) }) else {
            throw WindowToolError.invalidValue(name: "screen", expected: "an existing display (none is \(direction < 0 ? "left" : "right") of display \(current))", got: value)
        }
        return best
    }
    switch value {
    case "primary": return 0
    case "external":
        guard frames.count > 1 else {
            throw WindowToolError.invalidValue(name: "screen", expected: "an existing display (only the primary display is connected)", got: value)
        }
        return 1
    case "left": return try nearest(-1)
    case "right": return try nearest(1)
    case "next": return (current + 1) % frames.count
    case "prev": return (current + frames.count - 1) % frames.count
    default:
        throw WindowToolError.unknownChoice(kind: "screen", value: value, choices: ["<index>"] + screenNames)
    }
}

/// A display in the `screens` JSON schema, in the same global top-left coordinates windows use. `active-screen` prints the same object.
func screenJSON(index: Int, screen: NSScreen, mouseLocation: NSPoint) -> [String: Any] {
    let frame = cocoaToAX(rect: screen.frame)
    let visible = cocoaToAX(rect: screen.visibleFrame)
    return [
        "index": index,
        "frame_x": roundedInt(frame.origin.x), "frame_y": roundedInt(frame.origin.y),
        "frame_width": roundedInt(frame.width), "frame_height": roundedInt(frame.height),
        "visible_x": roundedInt(visible.origin.x), "visible_y": roundedInt(visible.origin.y),
        "visible_width": roundedInt(visible.width), "visible_height": roundedInt(visible.height),
        "scale": Double(screen.backingScaleFactor),
        "uuid": displayUUID(screen).map { $0 as Any } ?? NSNull(),
        "main": screen == NSScreen.main,
        "mouse": screen.frame.contains(mouseLocation)
    ]
}

/// Prints info for all connected displays in global top-left coordinates (the same ones `info` and `move` use).
/// Output columns: index, frame origin, frame size, visible origin, visible size, scale, and flags ([main], [mouse]).
func screensCommand() {
    let mouseLocation = NSEvent.mouseLocation
    let items = NSScreen.screens.enumerated().map { screenJSON(index: $0.offset, screen: $0.element, mouseLocation: mouseLocation) }
    if config.jsonOutput {
        printJSON(items)
    } else {
        print("INDEX\tFRAME_ORIGIN\tFRAME_SIZE\tVISIBLE_ORIGIN\tVISIBLE_SIZE\tSCALE\tFLAGS")
        for item in items {
            var flags: [String] = []
            if item["main"] as? Bool == true { flags.append("main") }
            if item["mouse"] as? Bool == true { flags.append("mouse") }
            let flagStr = flags.isEmpty ? "" : "[\(flags.joined(separator: ","))]"
            print("\(item["index"]!)\t\(item["frame_x"]!),\(item["frame_y"]!)\t\(item["frame_width"]!)x\(item["frame_height"]!)\t\(item["visible_x"]!),\(item["visible_y"]!)\t\(item["visible_width"]!)x\(item["visible_height"]!)\t\(item["scale"]!)\t\(flagStr)")
        }
    }
}

/// A window in the `info` JSON schema; mutating commands report the windows they changed in it too.
/// `list --fields` accepts these keys (see `listFieldNames`); add new keys there too.
func windowInfoJSON(_ w: WindowInfo, bundleId: String? = nil) -> [String: Any] {
    var dict: [String: Any] = [
        "title": w.title,
        "x": roundedInt(w.position.x), "y": roundedInt(w.position.y),
        "width": roundedInt(w.size.width), "height": roundedInt(w.size.height),
        "minimized": axBool(w.element, kAXMinimizedAttribute as String),
        "fullscreen": axBool(w.element, "AXFullScreen"),
        "focused": axBool(w.element, kAXFocusedAttribute as String),
        "main": axBool(w.element, kAXMainAttribute as String),
        "modal": axBool(w.element, "AXModal")
    ]
    if let bundleId = bundleId { dict["bundle_id"] = bundleId }
    if let parent = w.parentIndex { dict["parent_index"] = parent } else { dict["index"] = w.id }
    if let wid = w.windowID { dict["window_id"] = Int(wid) }
    if let role = axString(w.element, kAXRoleAttribute as String) { dict["role"] = role }
    if let subrole = axString(w.element, kAXSubroleAttribute as String) { dict["subrole"] = subrole }
    if let document = axString(w.element, kAXDocumentAttribute as String) { dict["document"] = document }
    return dict
}

/// Prints a window's details: the `info` JSON schema under `--json`, otherwise tab-separated key-value lines.
func printWindowInfo(_ w: WindowInfo, bundleId: String? = nil) {
    if config.jsonOutput {
        printJSON(windowInfoJSON(w, bundleId: bundleId))
    } else {
        let minimized = axBool(w.element, kAXMinimizedAttribute as String)
        let fullscreen = axBool(w.element, "AXFullScreen")
        let focused = axBool(w.element, kAXFocusedAttribute as String)
        let main = axBool(w.element, kAXMainAttribute as String)
        let modal = axBool(w.element, "AXModal")
        let role = axString(w.element, kAXRoleAttribute as String)
        let subrole = axString(w.element, kAXSubroleAttribute as String)
        let document = axString(w.element, kAXDocumentAttribute as String)
        if let bundleId = bundleId { print("bundle_id:\t\(bundleId)") }
        if let parent = w.parentIndex { print("parent_index:\t\(parent)") } else { print("index:\t\(w.id)") }
        if let wid = w.windowID { print("window_id:\t\(wid)") }
        print("title:\t\(w.title)")
        print("position:\t\(roundedInt(w.position.x)),\(roundedInt(w.position.y))")
        print("size:\t\(roundedInt(w.size.width))x\(roundedInt(w.size.height))")
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
        guard let wid = w.windowID else {
            throw WindowToolError.operationFailed("The active window has no window ID. Select a window with an index or title=<pattern> instead.")
        }
        if config.jsonOutput { printJSON(["window_id": Int(wid)]) } else { print(wid) }
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
        throw WindowToolError.unknownChoice(kind: "shell", value: shell, choices: ["zsh", "bash", "fish"])
    }
}

/// Prints the screen containing the mouse cursor: under `--json` the same object as its `screens` entry, otherwise its usable area.
func activeScreenCommand() {
    let mouseLocation = NSEvent.mouseLocation
    let screens = NSScreen.screens
    let index = screens.firstIndex { $0.frame.contains(mouseLocation) }
        ?? NSScreen.main.flatMap { screens.firstIndex(of: $0) } ?? 0
    let entry = screenJSON(index: index, screen: screens[index], mouseLocation: mouseLocation)
    if config.jsonOutput {
        printJSON(entry)
    } else {
        print("X\tY\tWIDTH\tHEIGHT")
        print("\(entry["visible_x"]!)\t\(entry["visible_y"]!)\t\(entry["visible_width"]!)\t\(entry["visible_height"]!)")
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

/// Keys `list --fields` accepts: the `list --json` schema.
let listFieldNames = ["app", "bundle_id", "index", "parent_index", "window_id", "title", "x", "y", "width", "height",
                      "minimized", "fullscreen", "focused", "main", "modal", "role", "subrole", "document",
                      "pid", "screen", "on_screen", "layer"]

/// Lists windows. When bundleId is provided, lists windows for that app only.
/// When nil, lists all windows across all running apps, sorted by app name.
/// The filters narrow that list: `titleGlob` (whole title, case-insensitive), `screen` (a `screens` index or name,
/// matched on the display holding the window's center), `visibleOnly` (on the current Space and not minimized) and
/// `excludeMinimized`. `sort` is `app` (the default), `title` or `id`.
/// `idsOnly` prints just the window IDs; `fields` (keys of the JSON schema, see `listFieldNames`) limits the output to those keys.
/// Windows with no title and no window ID are left out unless `includeAll`.
func listCommand(bundleId: String?, titleGlob: String? = nil, screen: String? = nil, visibleOnly: Bool = false,
                 excludeMinimized: Bool = false, sort: String = "app", idsOnly: Bool = false, fields: [String]? = nil,
                 includeAll: Bool = false) throws {
    struct WindowEntry {
        let app: String
        let bundleId: String
        let pid: pid_t?
        let window: WindowInfo
    }

    var entries: [WindowEntry] = []

    if let bundleId = bundleId {
        let appElement = try requireApp(bundleId)
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }
        let appName = running?.localizedName ?? bundleId
        for w in getWindows(appElement: appElement) {
            entries.append(WindowEntry(app: appName, bundleId: bundleId, pid: running?.processIdentifier, window: w))
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
                    entries.append(WindowEntry(app: appName, bundleId: bid, pid: app.processIdentifier, window: w))
                }
            }
        }
        entries.sort(by: { $0.app.lowercased() < $1.app.lowercased() })
    }

    let screenFrames = NSScreen.screens.map { cocoaToAX(rect: $0.frame) }
    func screenIndex(of w: WindowInfo) -> Int? {
        let center = CGPoint(x: w.position.x + w.size.width / 2, y: w.position.y + w.size.height / 2)
        return screenFrames.firstIndex(where: { $0.contains(center) })
    }
    let cgWindows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[CFString: Any]]) ?? []
    var cgByID: [CGWindowID: [CFString: Any]] = [:]
    for entry in cgWindows {
        if let number = entry[kCGWindowNumber] as? CGWindowID { cgByID[number] = entry }
    }

    if !includeAll {
        // Untitled windows without a window ID (such as Finder's desktop window) cannot be targeted by `id=` or `title=`.
        entries = entries.filter { !($0.window.title.isEmpty && $0.window.windowID == nil) }
    }
    if let glob = titleGlob {
        entries = entries.filter { fnmatch(glob, $0.window.title, FNM_CASEFOLD) == 0 }
    }
    if let screen = screen {
        // Relative names (left, right, next, prev) are relative to the display holding the mouse, as in active-screen.
        let mouse = NSEvent.mouseLocation
        let current = NSScreen.screens.firstIndex { $0.frame.contains(mouse) } ?? 0
        let wanted = try resolveScreenIndex(screen, frames: screenFrames, current: current)
        entries = entries.filter { screenIndex(of: $0.window) == wanted }
    }
    if excludeMinimized || visibleOnly {
        entries = entries.filter { !axBool($0.window.element, kAXMinimizedAttribute as String) }
    }
    if visibleOnly {
        entries = entries.filter { e in
            guard let wid = e.window.windowID, let cg = cgByID[wid] else { return false }
            return cg[kCGWindowIsOnscreen] as? Bool ?? false
        }
    }
    switch sort {
    case "title":
        entries.sort { $0.window.title.localizedCaseInsensitiveCompare($1.window.title) == .orderedAscending }
    case "id":
        entries.sort { ($0.window.windowID ?? .max) < ($1.window.windowID ?? .max) }
    default: break
    }

    if idsOnly {
        let ids = entries.compactMap { $0.window.windowID.map { Int($0) } }
        if config.jsonOutput { printJSON(ids) } else { ids.forEach { print($0) } }
    } else if config.jsonOutput || fields != nil {
        // `--fields` without --json also builds the JSON dicts, then prints the chosen keys as columns.
        let items = entries.map { e -> [String: Any] in
            let w = e.window
            var dict = windowInfoJSON(w, bundleId: e.bundleId)
            dict["app"] = e.app
            if let pid = e.pid { dict["pid"] = Int(pid) }
            if let screen = screenIndex(of: w) { dict["screen"] = screen }
            if let wid = w.windowID, let cg = cgByID[wid] {
                dict["on_screen"] = cg[kCGWindowIsOnscreen] as? Bool ?? false
                if let layer = cg[kCGWindowLayer] as? Int { dict["layer"] = layer }
            }
            if let fields = fields { dict = dict.filter { fields.contains($0.key) } }
            return dict
        }
        if config.jsonOutput {
            printJSON(items)
        } else if let fields = fields {
            print(fields.joined(separator: "\t"))
            for item in items {
                print(fields.map { item[$0].map { "\($0)" } ?? "" }.joined(separator: "\t"))
            }
        }
    } else {
        print("APP\tBUNDLE ID\tINDEX\tWID\tPOSITION\tSIZE\tTITLE")
        for e in entries {
            let w = e.window
            let wid = w.windowID.map { String($0) } ?? "?"
            print("\(e.app)\t\(e.bundleId)\t\(w.id)\t\(wid)\t\(roundedInt(w.position.x)),\(roundedInt(w.position.y))\t\(roundedInt(w.size.width))x\(roundedInt(w.size.height))\t\(w.title)")
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
    recordAffectedWindow(window.element)
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
    // Nothing dimmed means the desired end state already holds, so this is a quiet success.
    guard let pid = readPID(at: dimPIDFile) else { return }
    terminateOverlay(pid: pid)
    try? FileManager.default.removeItem(atPath: dimPIDFile)
}

func dimCommand(bundleId: String, selector: WindowSelector, opacity: Double, duration: Double) throws {
    guard opacity >= 0.0 && opacity <= 1.0 else {
        throw WindowToolError.invalidValue(name: "opacity", expected: "between 0.0 and 1.0", got: "\(opacity)")
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
    // Nothing dimmed means the desired end state already holds, so this is a quiet success.
    guard let pid = readPID(at: dimPIDFile) else { return }
    let terminated = terminateOverlay(pid: pid)
    try? FileManager.default.removeItem(atPath: dimPIDFile)
    if !terminated {
        throw WindowToolError.operationFailed("Dim process \(pid) is not running or is not a window-tool process")
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
        throw WindowToolError.appRequired(hint: "Use 'unborder <window>' with id=<N>, or 'unborder-all' to remove every border.")
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
    case leftThird = "left-third"
    case centerThird = "center-third"
    case rightThird = "right-third"
    case leftTwoThirds = "left-two-thirds"
    case rightTwoThirds = "right-two-thirds"

    static var allNames: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// The region as fractions of the visible frame. Add new positions that are plain regions here, not to the switch in snapCommand.
    var fractions: SnapFractions? {
        switch self {
        case .leftThird: return SnapFractions(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: return SnapFractions(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: return SnapFractions(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .leftTwoThirds: return SnapFractions(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: return SnapFractions(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        default: return nil
        }
    }
}

/// A region of the visible frame as fractions from 0 to 1, origin at the top left.
struct SnapFractions {
    let x, y, width, height: Double
}

/// Parses `--rect=x,y,w,h`: four fractions that must lie inside the visible frame.
func parseRectFlag(_ args: inout [String]) throws -> SnapFractions? {
    guard let value = try takeOption("--rect", from: &args) else { return nil }
    let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 4 else {
        throw WindowToolError.invalidValue(name: "rect", expected: "four comma-separated fractions: x,y,width,height", got: value)
    }
    let v = try zip(["x", "y", "width", "height"], parts).map { try parseDouble($1, label: "rect \($0)") }
    let eps = 1e-9
    guard v[0] >= 0, v[1] >= 0, v[2] > 0, v[3] > 0, v[0] + v[2] <= 1 + eps, v[1] + v[3] <= 1 + eps else {
        throw WindowToolError.invalidValue(name: "rect", expected: "fractions of the visible frame with x,y >= 0, width,height > 0, x+width <= 1 and y+height <= 1", got: value)
    }
    return SnapFractions(x: v[0], y: v[1], width: v[2], height: v[3])
}

/// Snaps a window to a named screen region, or to `rect` (fractions of the visible frame).
func snapCommand(bundleId: String, selector: WindowSelector, position: SnapPosition?, rect: SnapFractions? = nil) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let bounds = screenBoundsForWindow(window)
    let halfW = bounds.width / 2
    let halfH = bounds.height / 2

    if let f = rect ?? position?.fractions {
        moveWindow(window.element, x: bounds.x + bounds.width * f.x, y: bounds.y + bounds.height * f.y)
        resizeWindow(window.element, width: bounds.width * f.width, height: bounds.height * f.height)
        return
    }
    guard let position else { throw WindowToolError.missingArguments(command: "snap") }

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
    case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds:
        break // positions in `SnapPosition.fractions` return above
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
        throw WindowToolError.unknownChoice(kind: "side", value: side, choices: ["left", "right", "top", "bottom"])
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
                    x: roundedInt(win.position.x),
                    y: roundedInt(win.position.y),
                    width: roundedInt(win.size.width),
                    height: roundedInt(win.size.height)
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
        throw WindowToolError.nothingToUndo(command: "sidebar")
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
    recordAffectedWindow(window.element)
}

/// Exits macOS fullscreen mode for a window.
func unfullscreenCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, false as CFTypeRef)
    recordAffectedWindow(window.element)
}

/// Moves a window to a different screen, placing it at the top-left of the visible area.
func moveToScreenCommand(bundleId: String, selector: WindowSelector, screen: String) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let screens = NSScreen.screens
    let frames = screens.map { cocoaToAX(rect: $0.frame) }
    let center = CGPoint(x: window.position.x + window.size.width / 2, y: window.position.y + window.size.height / 2)
    let current = frames.firstIndex { $0.contains(center) } ?? 0
    let targetScreen = screens[try resolveScreenIndex(screen, frames: frames, current: current)]
    let visible = cocoaToAX(rect: targetScreen.visibleFrame)
    moveWindow(window.element, x: visible.origin.x, y: visible.origin.y)
}

/// Minimizes a window.
func minimizeCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, true as CFTypeRef)
    recordAffectedWindow(window.element)
}

/// Presses the close button of `windows` and waits for them to go. Throws `unsavedChanges` when a window answers with a
/// sheet and `operationFailed` when a window has no close button or is still open after the wait.
func closeWindows(_ windows: [WindowInfo]) throws {
    var pending: [WindowInfo] = []
    var failures: [String] = []
    for window in windows {
        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXCloseButtonAttribute as CFString, &buttonRef) == .success,
              let button = buttonRef,
              AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success else {
            failures.append("'\(window.title)' has no close button that can be pressed")
            continue
        }
        pending.append(window)
    }
    func isGone(_ window: WindowInfo) -> Bool {
        var pid: pid_t = 0
        // Gone once its attributes cannot be read or its app no longer lists it.
        guard currentFrame(of: window.element) != nil, AXUIElementGetPid(window.element, &pid) == .success else { return true }
        return !getWindows(appElement: AXUIElementCreateApplication(pid)).contains { CFEqual($0.element, window.element) }
    }
    func hasSheet(_ window: WindowInfo) -> Bool {
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window.element, kAXChildrenAttribute as CFString, &childrenRef)
        let children = childrenRef as? [AXUIElement] ?? []
        return children.contains { axString($0, kAXRoleAttribute as String) == kAXSheetRole as String }
    }
    // A window with unsaved changes stays open behind a sheet, so stop waiting for it as soon as the sheet shows.
    let deadline = Date().addingTimeInterval(2)
    var unsaved: [WindowInfo] = []
    while !pending.isEmpty {
        pending.removeAll { isGone($0) }
        let blocked = pending.filter { hasSheet($0) }
        unsaved += blocked
        pending.removeAll { w in blocked.contains { $0.id == w.id } }
        if pending.isEmpty || Date() >= deadline { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    if !unsaved.isEmpty { throw WindowToolError.unsavedChanges(windows: unsaved.map { ($0.windowID, $0.title) }) }
    failures += pending.map { "'\($0.title)' is still open after pressing its close button" }
    if !failures.isEmpty { throw WindowToolError.operationFailed("Not closed: " + failures.joined(separator: "; ")) }
}

/// Closes the selected window, or with no selector every window of the application, and succeeds only once they are gone.
func closeCommand(bundleId: String, selector: WindowSelector?) throws {
    let windows: [WindowInfo]
    if let selector {
        windows = [try resolveWindow(bundleId: bundleId, selector: selector)]
    } else {
        windows = getWindows(appElement: try requireApp(bundleId))
        guard !windows.isEmpty else { throw WindowToolError.noWindows }
    }
    try closeWindows(windows)
    printStatus("Closed \(windows.count) window(s)")
}

/// Asks every running instance of the app to quit (`terminate`, or `forceTerminate` with `force`) and waits up to
/// 5 seconds for it to exit. Throws `operationFailed` when it is still running, as when it is asking about unsaved changes.
func quitCommand(bundleId: String, force: Bool) throws {
    guard !bundleId.isEmpty else { throw WindowToolError.appRequired(hint: "quit closes one app.") }
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    guard let name = apps.first?.localizedName ?? apps.first?.bundleIdentifier else { throw WindowToolError.appNotFound(bundleId) }
    for app in apps { _ = force ? app.forceTerminate() : app.terminate() }
    let deadline = Date().addingTimeInterval(5)
    while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard apps.allSatisfy(\.isTerminated) else {
        throw WindowToolError.operationFailed("'\(name)' is still running after the quit request" + (force ? "." : "; it may be asking about unsaved changes. Answer it in the app, or use --force to discard them."))
    }
    if config.jsonOutput {
        printJSON(["quit": true, "app": name, "bundle_id": bundleId, "forced": force] as [String: Any])
    } else {
        print("Quit \(name)")
    }
}

/// Restores (unminimizes) the selected window, or every minimized window of the application when no selector is given.
func restoreCommand(bundleId: String, selector: WindowSelector?) throws {
    let windows: [AXUIElement]
    if let selector {
        windows = [try resolveWindow(bundleId: bundleId, selector: selector).element]
    } else {
        let app = try requireApp(bundleId)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        guard let all = windowsRef as? [AXUIElement] else { return }
        windows = all
    }
    var restored = 0
    for window in windows {
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
        if let minimized = minimizedRef as? Bool, minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            recordAffectedWindow(window)
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

// MARK: - Wait Command

/// Polls until the selected window exists (or with `gone`, no longer exists), and with `stable` has kept the same
/// frame for that long. Prints the matched window and throws `timedOut` after `timeout` seconds. The app may not be
/// running yet, so `--app` is resolved on every poll; `title=` waits for any match, as with `--first`.
func waitCommand(selector: WindowSelector, gone: Bool, stable: Double?, timeout: Double) throws {
    let target: String
    switch selector {
    case .byIndex(let index): target = "window \(index)"
    case .byTitle(let pattern): target = "a window titled '\(pattern)'"
    case .byWindowID(let windowID): target = "window id=\(windowID)"
    }
    func find() throws -> WindowInfo? {
        let savedFirstMatch = config.firstMatch
        config.firstMatch = true
        defer { config.firstMatch = savedFirstMatch }
        do {
            let bundleId = config.bundleId.isEmpty ? "" : try resolveAppIdentifier(config.bundleId)
            return try resolveWindow(bundleId: bundleId, selector: selector)
        } catch WindowToolError.appNotFound, WindowToolError.noWindowMatchingID, WindowToolError.noWindowMatchingTitle,
                WindowToolError.windowIndexOutOfRange {
            return nil
        }
    }
    func frame(_ w: WindowInfo) -> [Int] {
        [roundedInt(w.position.x), roundedInt(w.position.y), roundedInt(w.size.width), roundedInt(w.size.height)]
    }

    let deadline = Date().addingTimeInterval(timeout)
    var lastFrame: [Int]?
    var stableSince = Date()
    while true {
        let window = try find()
        if gone {
            if window == nil {
                if config.jsonOutput { printJSON(["gone": true] as [String: Any]) } else { print("Gone: \(target)") }
                return
            }
        } else if let window {
            if frame(window) != lastFrame {
                lastFrame = frame(window)
                stableSince = Date()
            }
            if Date().timeIntervalSince(stableSince) >= (stable ?? 0) {
                var pid: pid_t = 0
                AXUIElementGetPid(window.element, &pid)
                printWindowInfo(window, bundleId: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
                return
            }
        } else {
            lastFrame = nil
        }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            let what = gone ? "\(target) to go" : stable == nil ? "\(target) to exist" : "\(target) to stop moving and resizing"
            throw WindowToolError.timedOut(what: what, seconds: timeout)
        }
        Thread.sleep(forTimeInterval: min(0.1, remaining))
    }
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
        throw WindowToolError.optionRequired(option: "--output", command: "record", placeholder: "<path>")
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
                exitWithError(WindowToolError.operationFailed("Failed to start writing: \(assetWriter.error?.localizedDescription ?? "unknown")"))
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
                        exitWithError(WindowToolError.operationFailed("Recording failed: \(reason)"))
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
            exitWithError(WindowToolError.screenRecordingNotEnabled)
        } catch {
            setupError = error
            semaphore.signal()
        }
    }

    DispatchQueue.global().async {
        semaphore.wait()
        if let error = setupError {
            exitWithError(error)
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
            exitWithError(WindowToolError.operationFailed("Could not get window list"))
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

        exitWithError(WindowToolError.noPickableWindow)
    }

    app.run()
}

// MARK: - Layout Types

struct WindowSnapshot: Codable {
    let index: Int
    /// Absent in layouts saved before window IDs were recorded, and for windows without one.
    let windowID: Int?
    let title: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case index, title, x, y, width, height
        case windowID = "window_id"
    }
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
        WindowSnapshot(index: w.id, windowID: w.windowID.map { Int($0) }, title: w.title,
                       x: roundedInt(w.position.x), y: roundedInt(w.position.y),
                       width: roundedInt(w.size.width), height: roundedInt(w.size.height))
    }
    let layout = WindowLayout(bundleId: bundleId, windows: snapshots)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(layout)
    try data.write(to: URL(fileURLWithPath: filePath))
    if config.jsonOutput, var saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        saved["path"] = filePath
        // Each window object carries its owner's bundle_id like every other JSON window; the file keeps it once at the top.
        if let windows = saved["windows"] as? [[String: Any]] {
            saved["windows"] = windows.map { window -> [String: Any] in
                var window = window
                window["bundle_id"] = bundleId
                return window
            }
        }
        printJSON(saved)
    }
    printStatus("Saved \(windows.count) window(s) to \(filePath)")
}

/// Restores window positions and sizes from a previously saved layout file.
/// Matches each saved window to a current one by window ID, then title, then index; a current window is used at
/// most once. Saved windows with no match are skipped and reported as warnings.
func restoreLayoutCommand(filePath: String) throws {
    guard FileManager.default.fileExists(atPath: filePath) else {
        throw WindowToolError.fileNotFound(filePath)
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let layout = try JSONDecoder().decode(WindowLayout.self, from: data)
    let app = try requireApp(layout.bundleId)
    let currentWindows = getWindows(appElement: app)
    // WindowInfo.id is the position in getWindows, unique here (it is -1 only for windows outside that list).
    var claimed = Set<Int>()
    var matches: [Int: WindowInfo] = [:]
    let strategies: [(WindowSnapshot, WindowInfo) -> Bool] = [
        { saved, current in saved.windowID != nil && saved.windowID == current.windowID.map { Int($0) } },
        { saved, current in saved.title == current.title },
        // Last resort: whatever window now sits at the saved index, which may be an unrelated one.
        { saved, current in saved.index == current.id },
    ]
    for strategy in strategies {
        for (position, saved) in layout.windows.enumerated() where matches[position] == nil {
            if let match = currentWindows.first(where: { !claimed.contains($0.id) && strategy(saved, $0) }) {
                claimed.insert(match.id)
                matches[position] = match
            }
        }
    }
    for (position, saved) in layout.windows.enumerated() {
        guard let match = matches[position] else {
            let id = saved.windowID.map { ", id=\($0)" } ?? ""
            commandWarnings.append("no window matches saved '\(saved.title)' (index \(saved.index)\(id)); skipped")
            continue
        }
        moveWindow(match.element, x: CGFloat(saved.x), y: CGFloat(saved.y))
        resizeWindow(match.element, width: CGFloat(saved.width), height: CGFloat(saved.height))
    }
    printStatus("Restored \(matches.count)/\(layout.windows.count) window(s) for \(layout.bundleId)")
}

/// Cascades all windows for an application, offsetting each by a fixed amount.
func stackCommand(bundleId: String, selectors: [WindowSelector]?, offsetStep: Int) throws {
    let app = try requireApp(bundleId)
    var windows: [WindowInfo] = []
    if let selectors = selectors {
        for selector in selectors {
            windows.append(try resolveWindow(bundleId: bundleId, selector: selector))
        }
    } else {
        windows = getWindows(appElement: app)
    }
    if windows.isEmpty { return }
    let s = screenBoundsForWindow(windows[0])
    for (i, w) in windows.enumerated() {
        let offset = CGFloat(i * offsetStep)
        moveWindow(w.element, x: s.x + offset, y: s.y + offset)
    }
    printStatus("Stacked \(windows.count) window(s)")
}

/// Watches for window changes and prints updates. With `ndjson`, prints one compact event object per line
/// (`added`, `removed`, `moved`, `retitled`, keyed by window ID) and nothing for the starting state. `once` stops
/// after the first poll that changed something; `timeout` stops the watch after that long (exit 7 if `once`
/// saw nothing by then).
func watchCommand(bundleId: String, interval: Double, ndjson: Bool = false, once: Bool = false, timeout: Double? = nil) throws {
    let app = try requireApp(bundleId)

    struct WindowState: Equatable {
        let windowID: Int?
        let title: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    func snapshot() -> [WindowState] {
        let windows = getWindows(appElement: app)
        return windows.map {
            WindowState(windowID: $0.windowID.map { Int($0) }, title: $0.title,
                        x: roundedInt($0.position.x), y: roundedInt($0.position.y),
                        width: roundedInt($0.size.width), height: roundedInt($0.size.height))
        }
    }

    func printState(_ windows: [WindowState]) {
        if config.jsonOutput {
            let items = windows.enumerated().map { (i, w) in
                var dict: [String: Any] = ["bundle_id": bundleId, "index": i, "x": w.x, "y": w.y,
                                           "width": w.width, "height": w.height, "title": w.title]
                if let wid = w.windowID { dict["window_id"] = wid }
                return dict
            }
            printJSON(items)
        } else {
            for (i, w) in windows.enumerated() {
                print("\(i)\t\(w.x),\(w.y)\t\(w.width)x\(w.height)\t\(w.title)")
            }
        }
    }

    func emit(_ event: String, _ w: WindowState, index: Int, before: WindowState? = nil) {
        var dict: [String: Any] = ["event": event, "bundle_id": bundleId, "window_id": w.windowID ?? 0, "index": index,
                                   "x": w.x, "y": w.y, "width": w.width, "height": w.height, "title": w.title]
        if event == "retitled", let before { dict["previous_title"] = before.title }
        if event == "moved", let before {
            dict["previous"] = ["x": before.x, "y": before.y, "width": before.width, "height": before.height]
        }
        if config.jsonChaining {
            printJSON(dict)
        } else if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8) {
            print(line)
        }
    }

    /// Events between two snapshots, matched by window ID; windows without an ID are not tracked.
    func emitEvents(from old: [WindowState], to new: [WindowState]) -> Int {
        var count = 0
        var oldByID: [Int: WindowState] = [:]
        for w in old { if let id = w.windowID { oldByID[id] = w } }
        var seen = Set<Int>()
        for (i, w) in new.enumerated() {
            guard let id = w.windowID else { continue }
            seen.insert(id)
            guard let before = oldByID[id] else { emit("added", w, index: i); count += 1; continue }
            if (before.x, before.y, before.width, before.height) != (w.x, w.y, w.width, w.height) {
                emit("moved", w, index: i, before: before); count += 1
            }
            if before.title != w.title { emit("retitled", w, index: i, before: before); count += 1 }
        }
        for (i, w) in old.enumerated() {
            if let id = w.windowID, !seen.contains(id) { emit("removed", w, index: i); count += 1 }
        }
        return count
    }

    if !config.jsonOutput && !ndjson {
        print("INDEX\tPOSITION\tSIZE\tTITLE")
    }
    var previous = snapshot()
    if !ndjson {
        printState(previous)
        fflush(stdout)
    }

    signal(SIGINT) { _ in flushJSONAndExit(0) }

    let deadline = timeout.map { Date().addingTimeInterval($0) }
    while true {
        var pause = interval
        if let deadline {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                if once, let timeout { throw WindowToolError.timedOut(what: "a window change in \(bundleId)", seconds: timeout) }
                return
            }
            pause = min(pause, remaining)
        }
        Thread.sleep(forTimeInterval: pause)
        let current = snapshot()
        if current != previous {
            var changed = true
            if ndjson {
                changed = emitEvents(from: previous, to: current) > 0
            } else {
                if !config.jsonOutput { print("---") }
                printState(current)
            }
            fflush(stdout)
            previous = current
            if once && changed { return }
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
        throw WindowToolError.noWindows
    }

    let bounds = screenBoundsForWindow(windows[0])

    // Snapshot all windows before moving
    var snapshots: [TileWindowSnapshot] = []
    for win in windows {
        guard let wid = win.windowID else { continue }
        snapshots.append(TileWindowSnapshot(
            bundleId: bundleId,
            windowID: wid,
            x: roundedInt(win.position.x),
            y: roundedInt(win.position.y),
            width: roundedInt(win.size.width),
            height: roundedInt(win.size.height)
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
        throw WindowToolError.nothingToUndo(command: "tile")
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
/// `mutates` is true when the command changes a window's position, size, state or focus; under `--json` such a
/// command prints the windows it recorded with `recordAffectedWindow` (see `reportAffectedWindows`).
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
            let actsOnAll = ["move", "resize", "maximize"].contains(name)
            lines.append(actsOnAll ? "title= is a case-insensitive substring and acts on every matching window."
                                   : "title= is a case-insensitive substring; when several windows match it fails and lists them, unless --first is given.")
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
                summary: "List windows (all apps, or one app with --app)",
                flags: [("--title <glob>", "Only windows whose whole title matches the glob, case-insensitive (use '*PR*' for a substring)"),
                        ("--screen <screen>", "Only windows on a display: an index from 'screens', or primary, external, left, right, next, prev (relative to the mouse's display)"),
                        ("--visible", "Only windows that are on screen (not minimized, on the current Space)"),
                        ("--no-minimized", "Leave out minimized windows"),
                        ("--sort <key>", "Order by app (default), title or id"),
                        ("--all", "Include untitled windows that have no window ID (hidden by default; indexes count them either way)"),
                        ("--ids", "Print only window IDs, one per line (--json: an array of numbers)"),
                        ("--fields <a,b,c>", "Print only these fields (the --json keys, 'id' for window_id): tab-separated with a header, or --json objects")],
                resolvesOwnApp: true),
    CommandSpec(name: "info", group: .query, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Show detailed info for a window"),
    CommandSpec(name: "count", group: .query, app: .required, mutates: false,
                summary: "Print the number of windows for --app"),
    CommandSpec(name: "active-window", group: .query, app: .none, mutates: false,
                summary: "Print info about the frontmost app's primary window",
                flags: [("--id", "Print only the window ID")]),
    CommandSpec(name: "active-screen", group: .query, app: .none, mutates: false,
                summary: "Print the active screen's usable bounds (--json: its full screens entry)", needsAccessibility: false),
    CommandSpec(name: "screens", group: .query, app: .none, mutates: false,
                summary: "List all displays with bounds and scale in window coordinates", needsAccessibility: false),
    CommandSpec(name: "pick", group: .query, app: .none, mutates: false,
                summary: "Click a window to print its ID (blocks until you click)", needsAccessibility: false),
    CommandSpec(name: "watch", group: .query, app: .required, mutates: false, synopsis: "[--interval <seconds>] [--ndjson] [--once] [--timeout <seconds>]",
                summary: "Print window changes for --app until interrupted, --once or --timeout",
                arguments: [("[interval]", "Legacy form of --interval")],
                flags: [("--interval <seconds>", "Poll interval, greater than 0 (default: 1.0)"),
                        ("--ndjson", "Print one JSON event per line (added, removed, moved, retitled) instead of full snapshots"),
                        ("--once", "Stop after the first change (exit 7 if --timeout passes first)"),
                        ("--timeout <seconds>", "Stop watching after this long, greater than 0 (exit 0, or 7 with --once and no change)")]),

    CommandSpec(name: "wait", group: .query, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Block until a window exists, or with --gone is gone; exit 7 on timeout",
                flags: [("--gone", "Wait for the window to disappear instead of appear"),
                        ("--stable <seconds>", "Also wait until the window's position and size have not changed for this long, greater than 0"),
                        ("--timeout <seconds>", "Give up after this long, greater than 0 (default: 30)")],
                resolvesOwnApp: true),

    CommandSpec(name: "snap", group: .moveSize, app: .optional, mutates: true, synopsis: "<window> <position> | <window> --rect=<x,y,w,h>",
                summary: "Snap a window to a screen region",
                arguments: [("<position>", SnapPosition.allNames)],
                flags: [("--rect <x,y,w,h>", "Snap to a region given as fractions of the visible frame (0 to 1, origin top left) instead of a position, e.g. --rect=0,0,0.7,1")]),
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
                arguments: [("<screen>", "Display index from 'screens', or primary, external, left, right, next, prev")]),
    CommandSpec(name: "focus", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Bring a window to the front"),
    CommandSpec(name: "minimize", group: .moveSize, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Minimize a window"),
    CommandSpec(name: "close", group: .moveSize, app: .optional, mutates: true, synopsis: "<window> | --all",
                summary: "Close a window, or every window of --app with --all",
                flags: [("--all", "Close every window of --app instead of one window")]),
    // `mutates` means "prints a window list under --json"; quit prints its own result instead, so it stays false although it is destructive.
    CommandSpec(name: "quit", group: .moveSize, app: .required, mutates: false,
                summary: "Quit --app and wait until it has exited",
                flags: [("--force", "Force-terminate the app; unsaved changes are lost")], needsAccessibility: false),
    CommandSpec(name: "restore", group: .moveSize, app: .optional, mutates: true, synopsis: "[<window>]",
                summary: "Restore minimized windows: all for --app, or just <window>"),
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
    CommandSpec(name: "stack", group: .layout, app: .required, mutates: true, synopsis: "[<window>...] [--offset N]",
                summary: "Cascade the windows for --app, or just the ones named",
                arguments: [("[<window>...]", "Window selectors to cascade (default: all windows)"),
                            ("[offset]", "Legacy form of --offset: a lone bare number with no --offset")],
                flags: [("--offset N", "Pixels between each window (default: 30)")]),
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
    CommandSpec(name: "shake", group: .overlays, app: .optional, mutates: true, synopsis: "<window> [--offset N] [--count N] [--delay <seconds>]",
                summary: "Shake a window to draw attention to it",
                arguments: [("[offset] [count] [delay]", "Legacy forms of the options, in that order; not combined with them")],
                flags: [("--offset N", "Shake distance in pixels (default: 12)"),
                        ("--count N", "Number of shakes, greater than 0 (default: 6)"),
                        ("--delay <seconds>", "Seconds between movements (default: 0.04)")]),

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
    CommandSpec(name: "doctor", group: .meta, app: .none, mutates: false,
                summary: "Report the version and whether Accessibility and Screen Recording are granted",
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

/// Reports the version and the two permissions the tool depends on, so a script can check before it runs anything.
func doctorCommand() {
    let accessibility = AXIsProcessTrusted()
    let screenRecording = CGPreflightScreenCaptureAccess()
    if config.jsonOutput {
        printJSON(["version": VERSION, "accessibility": accessibility, "screenRecording": screenRecording] as [String: Any])
    } else {
        func row(_ name: String, _ granted: Bool, _ needed: String) -> String {
            "\(name.padding(toLength: 17, withPad: " ", startingAt: 0))\(granted ? "granted" : "missing")  (\(needed))"
        }
        print("window-tool \(VERSION)")
        print(row("Accessibility", accessibility, "needed by every command that reads or changes windows"))
        print(row("Screen Recording", screenRecording, "needed by preview and record"))
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
        "Usage: window-tool [--app <name-or-id>] [--json] [--keep-going] [--first] <command> [args...]",
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
        title=<pattern>     Case-insensitive substring of the window title (needs --app)
      move, resize and maximize act on every title match. Other commands fail when several
      windows match and list them; pass --first to use the first match instead.
      Use 'list' to see available indices and window IDs. Prefer id= in scripts.

    Snap positions:
      \(SnapPosition.allNames)

    Colors:
      \(validColors.joined(separator: ", "))

    Options:
      --app <name-or-id>  Target application by name or bundle ID
      --json              Output in JSON format
      --keep-going        In a chain, run the remaining commands after one fails
      --first             With title=, use the first match when several windows match (move, resize and maximize ignore it)
      --help, -h          Show help; after a command, show that command's help
      --version, -v       Print version and exit
      Options that take a value accept --flag value or --flag=value.
      Unknown options and extra arguments are errors; the command does not run.

    Output:
      Results go to stdout and errors to stderr. With --json, a command that changes
      windows prints {"windows": [...], "warnings": [...]} instead of a status message:
      each changed window in the info schema, plus "requested" if it was moved or resized.

    Errors and exit codes:
      With --json, an error also prints {"error": {"code", "message", "details"}}
      to stdout (in a chain, the failed command's "error"). Exit codes: 0 success,
      1 other failure, 2 usage error, 3 app not found or ambiguous, 4 window not
      found, 5 permission not granted (Accessibility, or Screen Recording for record),
      6 close blocked by an unsaved-changes prompt, 7 wait timed out.

    Warnings:
      After a move or resize, the window's frame is re-read. If a set call failed or
      the frame differs from the request by more than 2 points (a minimum size, a
      fullscreen window), stderr gets "Warning: '<title>': size requested WxH but is WxH" and the exit
      code stays 0. With --json the message is also in the result's "warnings".

    Command chaining:
      Use + to run multiple commands in sequence, sharing --app and --json flags.
      Subsequent commands inherit the window selector from the previous command.
      Bare numbers that fit a command's arguments are arguments (+ shake 20);
      use id= or title= to name another window:
      window-tool --app Safari snap 0 center + focus + highlight --color red
      window-tool --app iTerm info 0 + info 1
      window-tool focus id=2457 + highlight + dim id=2789

      A chain stops at the first failure unless --keep-going is given; the exit code
      is the first failure's. With --json, a chain prints one object:
      {"results": [{"command", "ok", "data" or "error"}...], "failed_at": N or null}
      where N is the 1-based number of the first failed command.

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
if let firstIdx = args.firstIndex(of: "--first") {
    config.firstMatch = true
    args.remove(at: firstIdx)
}
if let keepGoingIdx = args.firstIndex(of: "--keep-going") {
    config.keepGoing = true
    args.remove(at: keepGoingIdx)
}

// Parse --app flag
// A missing value (takeOption throws) and an empty one get the same error.
let missingApp = WindowToolError.invalidValue(name: "--app", expected: "an app name or bundle ID (e.g. --app Finder)", got: "")
do {
    if let app = try takeOption("--app", from: &args) {
        guard !app.isEmpty else { throw missingApp }
        config.bundleId = app
        config.appExplicit = true
    }
} catch {
    exitWithError(missingApp)
}

guard !args.isEmpty else {
    usage()
    exit(0)
}

if args.first == "--version" || args.first == "-v" {
    if config.jsonOutput {
        printJSON(["version": VERSION])
    } else {
        print("window-tool \(VERSION)")
    }
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
        let titleGlob = try takeOption("--title", from: &rest)
        let screen = try takeOption("--screen", from: &rest)
        let visibleOnly = takeFlag("--visible", from: &rest)
        let excludeMinimized = takeFlag("--no-minimized", from: &rest)
        let sort = try takeOption("--sort", from: &rest) ?? "app"
        guard ["app", "title", "id"].contains(sort) else {
            throw WindowToolError.unknownChoice(kind: "sort key", value: sort, choices: ["app", "title", "id"])
        }
        let includeAll = takeFlag("--all", from: &rest)
        let idsOnly = takeFlag("--ids", from: &rest)
        let fieldsArg = try takeOption("--fields", from: &rest)
        var fields: [String]?
        if let arg = fieldsArg {
            if idsOnly {
                throw WindowToolError.invalidValue(name: "--fields", expected: "left out when --ids is given (--ids prints only window IDs)", got: arg)
            }
            fields = arg.split(separator: ",", omittingEmptySubsequences: false).map { $0 == "id" ? "window_id" : String($0) }
            if let bad = fields?.first(where: { !listFieldNames.contains($0) }) {
                throw WindowToolError.unknownChoice(kind: "field", value: bad, choices: listFieldNames)
            }
        }
        try checkArgs(rest, command: command)
        let resolvedBundleId: String? = config.appExplicit ? try resolveAppIdentifier(config.bundleId) : nil
        try listCommand(bundleId: resolvedBundleId, titleGlob: titleGlob, screen: screen, visibleOnly: visibleOnly,
                        excludeMinimized: excludeMinimized, sort: sort, idsOnly: idsOnly, fields: fields, includeAll: includeAll)
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
        let rect = try parseRectFlag(&rest)
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: [rect == nil ? 1 : 0])
        if let rect {
            try checkArgs(values, command: command)
            try snapCommand(bundleId: config.bundleId, selector: selector, position: nil, rect: rect)
        } else {
            guard let posStr = values.first else {
                throw WindowToolError.missingArguments(command: "snap")
            }
            guard let position = SnapPosition(rawValue: posStr) else {
                throw WindowToolError.unknownChoice(kind: "position", value: posStr, choices: SnapPosition.allCases.map(\.rawValue))
            }
            try snapCommand(bundleId: config.bundleId, selector: selector, position: position)
        }
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
        try moveToScreenCommand(bundleId: config.bundleId, selector: selector, screen: screenArg)
    case "maximize":
        try maximizeCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "minimize":
        try minimizeCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "close":
        if takeFlag("--all", from: &rest) {
            try checkArgs(rest, command: command)
            guard !config.bundleId.isEmpty else { throw WindowToolError.appRequired(hint: "close --all closes the windows of one app.") }
            try closeCommand(bundleId: config.bundleId, selector: nil)
        } else {
            try closeCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
        }
    case "quit":
        let force = takeFlag("--force", from: &rest)
        try checkArgs(rest, command: command)
        try quitCommand(bundleId: config.bundleId, force: force)
    case "restore":
        let selector = rest.isEmpty ? nil : try resolveSelectorAndArgs(rest, command: command).selector
        try restoreCommand(bundleId: config.bundleId, selector: selector)
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
        var offset = try takeOption("--offset", from: &rest).map { try parseInt($0, label: "offset") }
        try rejectUnknownOptions(rest, command: command)
        // Without --offset, a lone bare number is the legacy [offset]; anything else is a list of selectors.
        if offset == nil, rest.count == 1, let legacy = Int(rest[0]) {
            offset = legacy
            rest = []
        }
        let selectors: [WindowSelector]? = rest.isEmpty ? nil : try rest.map { try parseWindowSelector($0) }
        try stackCommand(bundleId: config.bundleId, selectors: selectors, offsetStep: offset ?? 30)
    case "wait":
        let gone = takeFlag("--gone", from: &rest)
        let stableArg = try takeOption("--stable", from: &rest)
        let timeout = try takeOption("--timeout", from: &rest).map { try parsePositiveDouble($0, label: "timeout") } ?? 30
        let stable = try stableArg.map { try parsePositiveDouble($0, label: "stable") }
        if gone, let stableArg {
            throw WindowToolError.invalidValue(name: "--stable", expected: "left out when --gone is given (a window that is gone has no frame)", got: stableArg)
        }
        try waitCommand(selector: try resolveSelectorAndArgs(rest, command: command).selector, gone: gone, stable: stable, timeout: timeout)
    case "watch":
        let namedInterval = try takeOption("--interval", from: &rest)
        let ndjson = takeFlag("--ndjson", from: &rest)
        let once = takeFlag("--once", from: &rest)
        let watchTimeout = try takeOption("--timeout", from: &rest).map { try parsePositiveDouble($0, label: "timeout") }
        let positionalInterval = try checkArgs(rest, command: command, max: namedInterval == nil ? 1 : 0).first
        let interval = try (namedInterval ?? positionalInterval).map { try parsePositiveDouble($0, label: "interval") } ?? 1.0
        try watchCommand(bundleId: config.bundleId, interval: interval, ndjson: ndjson, once: once, timeout: watchTimeout)
    case "focus":
        try focusCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "fullscreen":
        try fullscreenCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "unfullscreen":
        try unfullscreenCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "shake":
        let namedOffset = try takeOption("--offset", from: &rest)
        let namedCount = try takeOption("--count", from: &rest)
        let namedDelay = try takeOption("--delay", from: &rest)
        // With any named option, bare numbers are only the window selector, never legacy [offset] [count] [delay].
        let named = namedOffset != nil || namedCount != nil || namedDelay != nil
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: named ? [0] : [0, 1, 2, 3])
        let legacyOffset = values.first
        let legacyCount = values.count >= 2 ? values[1] : nil
        let legacyDelay = values.count >= 3 ? values[2] : nil
        let offset = try (namedOffset ?? legacyOffset).map { try parseInt($0, label: "offset") } ?? 12
        let count = try (namedCount ?? legacyCount).map { try parsePositiveInt($0, label: "count") } ?? 6
        let delay = try (namedDelay ?? legacyDelay).map { try parseDouble($0, label: "delay") } ?? 0.04
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
    case "doctor":
        try checkArgs(rest, command: command)
        doctorCommand()
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

// With --keep-going, a failed command is reported and the chain goes on; the exit code is the first failure's.
var firstFailureCode: Int32?
for (index, group) in commandGroups.enumerated() {
    config.runningCommand = group[0]
    do {
        try runCommand(group)
        reportAffectedWindows(asJSON: config.jsonOutput && commandSpec(named: group[0])?.mutates == true)
        recordChainResult()
    } catch {
        affectedWindows = []
        commandWarnings = []
        var error = error
        if case WindowToolError.optionNeedsValue(let option, nil) = error {
            error = WindowToolError.optionNeedsValue(option, command: group[0])
        }
        let prefix = commandGroups.count > 1 ? "Error in command \(index + 1) (\(group[0]))" : "Error"
        guard config.keepGoing else { exitWithError(error, prefix: prefix) }
        let code = reportError(error, prefix: prefix).exitCode
        firstFailureCode = firstFailureCode ?? code
    }
}
flushJSONAndExit(firstFailureCode ?? 0)
