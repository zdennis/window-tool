import AVFoundation
import Cocoa
import Foundation
import ScreenCaptureKit

let VERSION = "0.19.0"

// MARK: - Configuration

struct Config {
    var bundleId: String = ""
    /// `--exact`: --app must be a running app's whole name or bundle ID, with no substring matching.
    var exactApp: Bool = false
    var jsonOutput: Bool = false
    var keepGoing: Bool = false
    /// `--verbose`: after a command that changes windows, print a line for each window it changed (text output only).
    var verbose: Bool = false
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
    /// Set by a mutating command that printed its own JSON result (`undo --list`), so no `{"windows", "warnings"}` result follows it.
    var printedOwnResult = false
    /// Set by `undo` (and its aliases) so the frames it restores are not saved as a new change; `recordUndoEntry` clears it.
    var skipUndoRecording = false
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
    // `app` is the bundle ID of the --app in effect (null when none, or when the command ignores --app).
    let usesApp = commandSpec(named: command).map { $0.app != .none } ?? false
    let app = usesApp && !config.bundleId.isEmpty ? try? resolveAppIdentifier(config.bundleId) : nil
    var entry: [String: Any] = ["command": command, "ok": error == nil, "app": app ?? NSNull()]
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
    /// `candidates` is non-nil under `--exact`: the running apps a substring match would have found.
    case appNotFound(String, candidates: [(name: String, bundleId: String)]? = nil)
    case ambiguousApp(query: String, matches: [(name: String, bundleId: String)])
    case windowIndexOutOfRange(index: Int, count: Int)
    case noWindowMatchingTitle(String)
    case ambiguousWindowTitle(pattern: String, matches: [(index: Int, windowID: CGWindowID?, title: String)])
    case noWindowMatchingID(CGWindowID)
    case screenIndexOutOfRange(index: Int, count: Int)
    case noWindows
    case noPickableWindow
    /// A `--path` index past the end: `parent` is the path of the element that has only `count` children.
    case noElementAtPath(path: String, parent: String, count: Int, windowID: CGWindowID?)
    /// `text --focused` found no focused element in the window (or under `--path`).
    case noFocusedElement(windowID: CGWindowID?, path: String)
    /// `press --role`/`--title` matched no element at or below `path`.
    case noMatchingElement(role: String?, title: String?, path: String, windowID: CGWindowID?)
    /// `press --role`/`--title` matched more than one element at or below `path`.
    case ambiguousElement(role: String?, title: String?, path: String, matches: [ElementMatch], windowID: CGWindowID?)
    /// `press` was pointed at a password field or an element inside one, which it never acts on.
    case secureElement(path: String, windowID: CGWindowID?)
    /// The element `press` found does not offer the action; `actions` are the ones it does offer.
    case actionNotSupported(action: String, path: String, actions: [String], windowID: CGWindowID?)
    /// A window answered the close with a sheet (such as "Do you want to save changes?") instead of closing.
    case unsavedChanges(windows: [(windowID: CGWindowID?, title: String)])
    /// `wait` ran out of time; `what` finishes the sentence "Timed out after Ns waiting for ...".
    case timedOut(what: String, seconds: Double)
    case accessibilityNotEnabled
    case screenRecordingNotEnabled
    case invalidValue(name: String, expected: String, got: String)
    case unknownChoice(kind: String, value: String, choices: [String])
    case optionRequired(option: String, command: String, placeholder: String)
    /// `command` is nil for `undo`, or names the command whose change `tile --untile` or `sidebar --unpush` looked for.
    case nothingToUndo(command: String?)
    /// `hint` says where to look next (for a named layout, the `layouts` command).
    case fileNotFound(String, hint: String? = nil)
    /// `hint` replaces the default pointer to id= for commands where a window ID does not help.
    case appRequired(hint: String? = nil)
    /// `hint` is added after the first line (the main loop's catch adds one when a change of --app dropped the inherited selector).
    case missingWindowSelector(command: String, hint: String? = nil)
    case unknownOption(String, command: String)
    /// `command` is nil for a repeated global flag (--json, --first, --keep-going, --exact, --verbose), which belongs to no command, and for an --app repeated in a chain part that has no command.
    case repeatedOption(String, command: String?)
    case unexpectedArgument(String, command: String, conflictsWith: String? = nil)
    /// `command` is nil when thrown by takeOption; the top-level catch fills it in.
    case optionNeedsValue(String, command: String?)
    case optionTakesNoValue(String, command: String)
    case missingArguments(command: String)
    case unknownCommand(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let id, nil):
            return "Application not found: \(id)"
        case .appNotFound(let id, let candidates?):
            let list = candidates.map { "\n  \($0.name) (\($0.bundleId))" }.joined()
            return "Application not found: \(id). --exact matches a whole app name or bundle ID; drop it for substring matching"
                + (candidates.isEmpty ? "." : ", which would match:\(list)")
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
        case .noElementAtPath(let path, let parent, let count, let windowID):
            let owner = parent.isEmpty ? "the window" : "element \(parent)"
            let tree = windowID.map { "'window-tool tree id=\($0)'" } ?? "'window-tool tree'"
            return "No element at path '\(path)': \(owner) has \(count == 0 ? "no children" : "children 0..\(count - 1)"). Paths change when the window's UI does; run \(tree) again."
        case .noFocusedElement(let windowID, let path):
            let window = windowID.map { "window id=\($0)" } ?? "the window"
            let focus = windowID.map { "'window-tool focus id=\($0)'" } ?? "'window-tool focus'"
            return "No element \(path.isEmpty ? "in \(window)" : "under path \(path) of \(window)") has keyboard focus. Focus belongs to the app, so another of its windows may hold it: click into a field or run \(focus) first."
        case .noMatchingElement(let role, let title, let path, let windowID):
            let tree = windowID.map { "'window-tool tree id=\($0)'" } ?? "'window-tool tree'"
            return "No element \(elementQuery(role: role, title: title)) \(path.isEmpty ? "in the window" : "at or below path \(path)"). Run \(tree) to see roles, titles and paths." + (title == nil ? "" : " Toolbar buttons often have only a description and no title; press those with --path.")
        case .ambiguousElement(let role, let title, let path, let matches, _):
            let list = matches.map { "  " + describeElement($0) }.joined(separator: "\n")
            let missing = [role == nil ? "--role" : nil, title == nil ? "--title" : nil].compactMap { $0 }
            let hint = missing.isEmpty ? "Narrow the search with --path <subtree>, or press one of the paths above with --path."
                                       : "Add \(missing.joined(separator: " or ")) to narrow it, or use --path with one of the paths above."
            return "\(matches.count) elements match \(elementQuery(role: role, title: title)) \(path.isEmpty ? "in the window" : "at or below path \(path)"):\n\(list)\n\(hint)"
        case .secureElement(let path, _):
            return "\(path.isEmpty ? "The window" : "Element [\(path)]") is a password field or inside one. press never acts on those, to keep passwords out of scripts' and agents' output and actions."
        case .actionNotSupported(let action, let path, let actions, _):
            let offered = actions.isEmpty ? "it offers no actions." : "it offers only \(actions.map(treeDisplayAction).joined(separator: ", ")). Pass one of those with --action."
            return "\(path.isEmpty ? "The window" : "Element [\(path)]") does not offer \(treeEscape(action)); \(offered)"
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
            return "Nothing to undo. " + (command.map { "Run '\($0)' first." } ?? "Commands that move or resize windows add to the undo history; it is cleared on restart.")
        case .fileNotFound(let path, let hint):
            return "File not found: \(path)" + (hint.map { ". \($0)" } ?? "")
        case .appRequired(let hint):
            return "--app <name> is required for this command. " + (hint ?? WindowToolError.appRequiredHint)
        case .missingWindowSelector(let command, let hint):
            return "Missing window selector for '\(command)'. Use an index (0, 1, ...), id=<N>, or title=<pattern>.\n" + (hint.map { "\($0)\n" } ?? "")
                + "Run 'window-tool \(command) --help' for usage."
        case .unknownOption(let option, let command):
            return "Unknown option '\(option)' for '\(command)'. Run 'window-tool \(command) --help'."
        case .repeatedOption(let option, let command):
            return "Option '\(option)' given more than once" + (command.map { " for '\($0)'. Run 'window-tool \($0) --help'." } ?? ". Give it once. Run 'window-tool help'.")
        case .unexpectedArgument(let arg, let command, let other?):
            return "\(arg) and \(other) are alternatives; use one. Run 'window-tool \(command) --help'."
        case .unexpectedArgument(let arg, let command, nil):
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

    static let appRequiredHint = "When selecting a window, id=<N> works without it; run 'window-tool list' to see window IDs."

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
        case .noElementAtPath: return "no_element_at_path"
        case .noFocusedElement: return "no_focused_element"
        case .noMatchingElement: return "no_matching_element"
        case .ambiguousElement: return "ambiguous_element"
        case .secureElement: return "secure_element"
        case .actionNotSupported: return "action_not_supported"
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
        case .appNotFound(let app, nil):
            return ["app": app, "exact": false]
        case .appNotFound(let app, let candidates?):
            return ["app": app, "exact": true, "candidates": candidates.map { ["name": $0.name, "bundle_id": $0.bundleId] }]
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
        case .noElementAtPath(let path, let parent, let count, let windowID):
            return ["path": path, "parent": parent, "count": count, "window_id": windowID.map { Int($0) } ?? NSNull()]
        case .noFocusedElement(let windowID, let path), .secureElement(let path, let windowID):
            return ["window_id": windowID.map { Int($0) } ?? NSNull(), "path": path]
        case .noMatchingElement(let role, let title, let path, let windowID):
            return elementMatchJSON((path, role, title)).merging(["window_id": windowID.map { Int($0) } ?? NSNull()]) { $1 }
        case .ambiguousElement(let role, let title, let path, let matches, let windowID):
            return elementMatchJSON((path, role, title)).merging(["window_id": windowID.map { Int($0) } ?? NSNull(),
                                                                  "matches": matches.map(elementMatchJSON)]) { $1 }
        case .actionNotSupported(let action, let path, let actions, let windowID):
            return ["action": action, "path": path, "actions": actions, "window_id": windowID.map { Int($0) } ?? NSNull()]
        case .invalidValue(let name, let expected, let got):
            return ["name": name, "expected": expected, "got": got]
        case .unknownChoice(let kind, let value, let choices):
            return ["kind": kind, "value": value, "choices": choices]
        case .optionRequired(let option, let command, _):
            return ["option": option, "command": command]
        case .nothingToUndo(let command):
            return ["command": command ?? NSNull()]
        case .missingWindowSelector(let command, _), .missingArguments(let command):
            return ["command": command]
        case .fileNotFound(let path, _):
            return ["path": path]
        case .timedOut(let what, let seconds):
            return ["waiting_for": what, "timeout": seconds]
        case .unsavedChanges(let windows):
            return ["windows": windows.map { ["window_id": $0.windowID.map { Int($0) } ?? NSNull(), "title": $0.title] as [String: Any] }]
        case .unknownOption(let option, let command), .optionTakesNoValue(let option, let command):
            return ["option": option, "command": command]
        case .repeatedOption(let option, let command):
            return ["option": option, "command": command ?? NSNull()]
        case .unexpectedArgument(let argument, let command, let other):
            var details: [String: Any] = ["argument": argument, "command": command]
            if let other { details["conflicts_with"] = other }
            return details
        case .optionNeedsValue(let option, let command):
            return ["option": option, "command": command ?? NSNull()]
        case .unknownCommand(let command):
            return ["command": command, "suggestion": closestCommandName(to: command) ?? NSNull()]
        case .noWindows, .noPickableWindow, .accessibilityNotEnabled, .screenRecordingNotEnabled, .appRequired, .operationFailed:
            return [:]
        }
    }

    /// 2 usage, 3 app not found, 4 window or element not found, 5 permission denied, 6 unsaved changes blocked a close, 7 a wait or watch --once timed out, 1 anything else.
    var exitCode: Int32 {
        switch self {
        case .invalidValue, .unknownChoice, .optionRequired, .appRequired, .missingWindowSelector, .unknownOption,
             .repeatedOption, .unexpectedArgument, .optionNeedsValue, .optionTakesNoValue, .missingArguments, .unknownCommand,
             .screenIndexOutOfRange:
            return 2
        case .appNotFound, .ambiguousApp:
            return 3
        case .windowIndexOutOfRange, .noWindowMatchingTitle, .ambiguousWindowTitle, .noWindowMatchingID, .noWindows, .noPickableWindow,
             .noElementAtPath, .noFocusedElement, .noMatchingElement, .ambiguousElement:
            return 4
        case .accessibilityNotEnabled, .screenRecordingNotEnabled:
            return 5
        case .unsavedChanges:
            return 6
        case .timedOut:
            return 7
        case .nothingToUndo, .fileNotFound, .secureElement, .actionNotSupported, .operationFailed:
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

// `label` becomes the error message subject and `details.name` of `invalid_value`. A value from an option uses the
// option as spelled (`--opacity`, `--size`); a positional argument uses a bare word (`index`, `x`, `width`), and so do
// the legacy positional forms of shake and watch.
func parseInt(_ s: String, label: String) throws -> Int {
    guard let v = Int(s) else {
        throw WindowToolError.invalidValue(name: label, expected: "a whole number", got: s)
    }
    return v
}

/// Largest magnitude accepted for a coordinate or size; far beyond any display, and safe to round to Int.
let maxCoordinate = 1e12

func parseDouble(_ s: String, label: String) throws -> Double {
    guard let v = Double(s), v.isFinite, abs(v) <= maxCoordinate else {
        throw WindowToolError.invalidValue(name: label, expected: "a finite number no larger than 1e12 in magnitude", got: s)
    }
    return v
}

func parsePositiveInt(_ s: String, label: String) throws -> Int {
    guard let v = Int(s), v > 0 else {
        throw WindowToolError.invalidValue(name: label, expected: "a whole number greater than 0", got: s)
    }
    return v
}

/// A whole number 0 or more, and at most `max` when given.
func parseNonNegativeInt(_ s: String, label: String, max: Int? = nil) throws -> Int {
    guard let v = Int(s), v >= 0, v <= max ?? Int.max else {
        throw WindowToolError.invalidValue(name: label, expected: max.map { "a whole number from 0 to \($0)" } ?? "a whole number, 0 or more", got: s)
    }
    return v
}

func parsePositiveDouble(_ s: String, label: String) throws -> Double {
    guard let v = Double(s), v.isFinite, v > 0 else {
        throw WindowToolError.invalidValue(name: label, expected: "a number greater than 0", got: s)
    }
    return v
}

/// An overlay's `--duration` (highlight, dim, identify): 0 to 86400 seconds (one day). The capture commands
/// (record, pip) take any positive `--duration` through `parsePositiveDouble` instead.
func parseOverlayDuration(_ s: String) throws -> Double {
    guard let v = Double(s), v >= 0, v <= 86400 else {
        throw WindowToolError.invalidValue(name: "--duration", expected: "a number of seconds from 0 to 86400", got: s)
    }
    return v
}

/// A capture `--fps`: 1 to 120, capped so CMTimeScale (an Int32) cannot overflow.
func parseFps(_ s: String) throws -> Int {
    guard let v = Int(s), (1...120).contains(v) else {
        throw WindowToolError.invalidValue(name: "--fps", expected: "a whole number from 1 to 120", got: s)
    }
    return v
}

/// A duration for messages: whole seconds without a decimal point (`10s`), otherwise as given (`0.5s`).
func formatSeconds(_ seconds: Double) -> String {
    seconds == seconds.rounded() ? "\(Int(seconds))s" : "\(seconds)s"
}

/// `s` as one shell word, for commands suggested in messages: unchanged when it is only letters, digits and `-_./`,
/// otherwise single-quoted with each `'` written as `'\''`, so no character (`$`, `!`, a space) is expanded.
func shellQuoted(_ s: String) -> String {
    s.allSatisfy { $0.isLetter || $0.isNumber || "-_./".contains($0) } ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
    let known = ["--json"] + specFlags.map { String($0.prefix { $0 != " " }) }
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
    let count = try takeOption("--count", from: &args).map { try parsePositiveInt($0, label: "--count") } ?? 1
    return (color, count)
}

func parseHighlightFlags(_ args: inout [String]) throws -> (color: NSColor, duration: Double) {
    let color = try takeOption("--color", from: &args).map(parseColor) ?? .red
    let duration = try takeOption("--duration", from: &args).map(parseOverlayDuration) ?? 3.0
    return (color, duration)
}

func parseBorderFlags(_ args: inout [String]) throws -> (color: NSColor, width: CGFloat) {
    let color = try takeOption("--color", from: &args).map(parseColor) ?? .blue
    let width = try takeOption("--width", from: &args).map { CGFloat(try parseDouble($0, label: "--width")) } ?? 3
    return (color, width)
}

func parseSizeFlag(_ args: inout [String]) throws -> (CGFloat, CGFloat)? {
    guard let value = try takeOption("--size", from: &args) else { return nil }
    if let sep = value.firstIndex(of: ",") ?? value.firstIndex(of: "x") {
        let wStr = String(value[value.startIndex..<sep])
        let hStr = String(value[value.index(after: sep)...])
        let w = CGFloat(try parseDouble(wStr, label: "--size"))
        let h = CGFloat(try parseDouble(hStr, label: "--size"))
        return (w, h)
    }
    let n = CGFloat(try parseDouble(value, label: "--size"))
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
    let gap = try takeOption("--gap", from: &args).map { try parseInt($0, label: "--gap") } ?? 10
    let cols = try takeOption("--cols", from: &args).map { try parsePositiveInt($0, label: "--cols") }
    let untile = takeFlag("--untile", from: &args)
    return (gap, cols, untile)
}

// MARK: - Undo History

/// Per-user (in `$TMPDIR`, so it is gone after a restart); holds the last `undoHistoryLimit` geometry changes, oldest first.
let undoHistoryFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("window-tool-undo-history.json")
let undoHistoryLimit = 20

/// A window's frame before a command moved or resized it.
struct UndoWindowFrame: Codable {
    let bundleId: String?
    let windowID: UInt32
    let title: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case title, x, y, width, height
        case bundleId = "bundle_id"
        case windowID = "window_id"
    }
}

/// One command's geometry change: the command line and the frames it replaced.
struct UndoEntry: Codable {
    let command: String
    let arguments: [String]
    let time: Date
    let windows: [UndoWindowFrame]
}

/// The undo history, oldest first; empty when there is none, or (with a command warning) when the file cannot be decoded.
func loadUndoHistory() -> [UndoEntry] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: undoHistoryFile)) else { return [] }
    guard let history = try? decoder.decode([UndoEntry].self, from: data) else {
        commandWarnings.append("could not read the undo history at \(undoHistoryFile); treating it as empty, and the next change replaces it")
        return []
    }
    return history
}

func saveUndoHistory(_ history: [UndoEntry]) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(Array(history.suffix(undoHistoryLimit))).write(to: URL(fileURLWithPath: undoHistoryFile), options: .atomic)
}

// MARK: - Accessibility Helpers

/// Resolves an app identifier to a bundle ID.
/// An exact bundle ID wins. Otherwise, an exact case-insensitive app name wins; failing that, it's matched
/// case-insensitively as a substring of app names and bundle IDs of running apps.
/// With `--exact`, only a whole name or bundle ID (ignoring case) matches, so a newly launched app cannot make it ambiguous.
func resolveAppIdentifier(_ identifier: String) throws -> String {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

    // Try exact bundle ID match first
    if apps.contains(where: { $0.bundleIdentifier == identifier }) {
        return identifier
    }

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
    if config.exactApp {
        let substringMatches = matches
        matches = matches.filter { $0.name.lowercased() == query || $0.bundleId.lowercased() == query }
        if matches.isEmpty { throw WindowToolError.appNotFound(identifier, candidates: substringMatches) }
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
func roundedInt(_ v: CGFloat) -> Int { v.isNaN ? 0 : Int(max(-maxCoordinate, min(maxCoordinate, Double(v))).rounded()) }

/// A frame as whole points, for telling whether a window ended where it started.
func roundedFrame(_ r: CGRect) -> [Int] { [r.origin.x, r.origin.y, r.width, r.height].map(roundedInt) }

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

/// Decodes a point or size from an AX attribute value, or returns nil when the value is missing, is another type,
/// or is the error value `AXUIElementCopyMultipleAttributeValues` returns for a missing attribute.
func axValue<T: BitwiseCopyable>(_ ref: Any?, _ type: AXValueType, _ empty: T) -> T? {
    guard let ref, CFGetTypeID(ref as CFTypeRef) == AXValueGetTypeID() else { return nil }
    var value = empty
    return AXValueGetValue(ref as! AXValue, type, &value) ? value : nil
}

/// Builds a WindowInfo from an AXUIElement window, or returns nil if position/size can't be read.
func makeWindowInfo(element: AXUIElement, id: Int, parentIndex: Int? = nil) -> WindowInfo? {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    let title = titleRef as? String ?? ""

    var posRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
    let position = axValue(posRef, .cgPoint, CGPoint.zero) ?? .zero

    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
    let size = axValue(sizeRef, .cgSize, CGSize.zero) ?? .zero

    return WindowInfo(element: element, id: id, parentIndex: parentIndex, title: title, position: position, size: size, windowID: getCGWindowID(element))
}

/// Reads a window's current top-left frame, or returns nil once the window no longer exists.
func currentFrame(of element: AXUIElement) -> CGRect? {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let position = axValue(posRef, .cgPoint, CGPoint.zero),
          let size = axValue(sizeRef, .cgSize, CGSize.zero) else {
        return nil
    }
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
    /// The frame before the command's first move or resize, saved for `undo` by `recordUndoEntry`.
    var before: CGRect?
}

var affectedWindows: [AffectedWindow] = []

/// Warnings a command adds on its own (for example saved windows `restore-layout` could not match); reported with the frame warnings.
var commandWarnings: [String] = []

/// Fields a command adds to its `--json` result next to `windows` and `warnings` (restore-layout's `restored` and `total`).
var commandResultFields: [String: Any] = [:]

/// Records that the running command changed `window`. moveWindow/resizeWindow call it with what they requested;
/// commands that change a window another way (focus, minimize, fullscreen) call it themselves.
func recordAffectedWindow(_ window: AXUIElement, position: CGPoint? = nil, size: CGSize? = nil, failure: String? = nil, before: CGRect? = nil) {
    let index = affectedWindows.firstIndex { CFEqual($0.element, window) } ?? {
        affectedWindows.append(AffectedWindow(element: window))
        return affectedWindows.count - 1
    }()
    affectedWindows[index].position = position ?? affectedWindows[index].position
    affectedWindows[index].size = size ?? affectedWindows[index].size
    affectedWindows[index].before = affectedWindows[index].before ?? before
    if let failure { affectedWindows[index].failures.append(failure) }
}

/// The window's frame before the running command first moves or resizes it, or nil once that frame has been recorded.
/// A window recorded without one (focused or minimized earlier in the command) still gets it on its first move.
func frameBeforeFirstChange(_ window: AXUIElement) -> CGRect? {
    affectedWindows.first { CFEqual($0.element, window) }?.before != nil ? nil : currentFrame(of: window)
}

/// Moves a window to the specified screen coordinates.
/// It also captures the window's previous frame for `undo`, so every geometry change must go through moveWindow or resizeWindow.
func moveWindow(_ window: AXUIElement, x: CGFloat, y: CGFloat) {
    var point = CGPoint(x: x, y: y)
    guard let value = AXValueCreate(.cgPoint, &point) else { return }
    let before = frameBeforeFirstChange(window)
    let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    recordAffectedWindow(window, position: point, failure: result == .success ? nil : "could not set position (AXError \(result.rawValue))", before: before)
}

/// Resizes a window to the specified width and height. Like moveWindow, it captures the previous frame for `undo`.
func resizeWindow(_ window: AXUIElement, width: CGFloat, height: CGFloat) {
    var size = CGSize(width: width, height: height)
    guard let value = AXValueCreate(.cgSize, &size) else { return }
    let before = frameBeforeFirstChange(window)
    let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    recordAffectedWindow(window, size: size, failure: result == .success ? nil : "could not set size (AXError \(result.rawValue))", before: before)
}

/// Runs after each command, before `reportAffectedWindows`. Appends the frames the command replaced to the undo
/// history: every window it moved or resized that has a window ID and ended up somewhere else (so `shake`, which
/// returns the window to where it was, adds nothing). A history that cannot be written becomes a warning.
func recordUndoEntry(_ args: [String]) {
    defer { config.skipUndoRecording = false }
    guard !config.skipUndoRecording else { return }
    let frames: [UndoWindowFrame] = affectedWindows.compactMap { affected in
        guard let before = affected.before, let windowID = getCGWindowID(affected.element),
              let after = currentFrame(of: affected.element) else { return nil }
        guard roundedFrame(before) != roundedFrame(after) else { return nil }
        var pid: pid_t = 0
        let bundleId = AXUIElementGetPid(affected.element, &pid) == .success ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
        return UndoWindowFrame(bundleId: bundleId, windowID: windowID, title: axString(affected.element, kAXTitleAttribute as String) ?? "",
                               x: roundedInt(before.origin.x), y: roundedInt(before.origin.y),
                               width: roundedInt(before.width), height: roundedInt(before.height))
    }
    guard !frames.isEmpty else { return }
    do {
        try saveUndoHistory(loadUndoHistory() + [UndoEntry(command: args[0], arguments: Array(args.dropFirst()), time: Date(), windows: frames)])
    } catch {
        commandWarnings.append("could not save the undo history to \(undoHistoryFile): \(error.localizedDescription)")
    }
}

/// Runs after each command. Re-reads every window it changed and prints `Warning: ...` to stderr for each set
/// call that failed or left the frame more than 2 points from the request. With `asJSON` (a mutating command
/// under `--json`) it prints the command's result: `{"windows": [...], "warnings": [...]}`, each window in the
/// `info` schema after the change plus `requested` when a frame was asked for. Clears the recorded windows.
func reportAffectedWindows(asJSON: Bool) {
    defer { affectedWindows = []; commandWarnings = []; commandResultFields = [:] }
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
    if asJSON { printJSON(commandResultFields.merging(["windows": windows, "warnings": warnings]) { $1 }) }
}

/// Under `--verbose` without `--json`, runs before `reportAffectedWindows` and prints one line per window the command
/// changed without a failed set call: `Moved "Notes" "Todo" (id=1341) to 100,50 800x600`. A window that was moved or
/// resized ends with `to` and its whole frame re-read after the change, unless it ended where it started (shake).
func printConfirmations(verb: String) {
    let quoted = { (s: String?) in s.flatMap { $0.isEmpty ? nil : "\"\(treeEscape($0))\"" } }
    for affected in affectedWindows where affected.failures.isEmpty {
        var pid: pid_t = 0
        let app = AXUIElementGetPid(affected.element, &pid) == .success
            ? NSRunningApplication(processIdentifier: pid).flatMap { quoted($0.localizedName ?? $0.bundleIdentifier) } : nil
        var line = [verb, app, quoted(axString(affected.element, kAXTitleAttribute as String)) ?? "window"].compactMap { $0 }.joined(separator: " ")
        if let id = getCGWindowID(affected.element) { line += " (id=\(id))" }
        if let after = currentFrame(of: affected.element), let before = affected.before, roundedFrame(before) != roundedFrame(after) {
            line += " to \(roundedInt(after.origin.x)),\(roundedInt(after.origin.y)) \(roundedInt(after.width))x\(roundedInt(after.height))"
        }
        print(line)
    }
    fflush(stdout)
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
        for child in axChildren(parent.element) {
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
/// `primary` is index 0 and `external` index 1: `screens` lists the primary display first.
/// `label` names the value in errors: `--screen` for list's option, the bare `screen` for move-to-screen's positional.
func resolveScreenIndex(_ value: String, frames: [CGRect], current: Int, label: String = "screen") throws -> Int {
    if let index = Int(value) {
        guard frames.indices.contains(index) else {
            throw WindowToolError.screenIndexOutOfRange(index: index, count: frames.count)
        }
        return index
    }
    func nearest(_ direction: CGFloat) throws -> Int {
        let candidates = frames.indices.filter { (frames[$0].midX - frames[current].midX) * direction > 0 }
        guard let best = candidates.min(by: { abs(frames[$0].midX - frames[current].midX) < abs(frames[$1].midX - frames[current].midX) }) else {
            throw WindowToolError.invalidValue(name: label, expected: "an existing display (none is \(direction < 0 ? "left" : "right") of display \(current))", got: value)
        }
        return best
    }
    switch value {
    case "primary": return 0
    case "external":
        guard frames.count > 1 else {
            throw WindowToolError.invalidValue(name: label, expected: "an existing display (only the primary display is connected)", got: value)
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
        let wanted = try resolveScreenIndex(screen, frames: screenFrames, current: current, label: "--screen")
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
    let opacity = try takeOption("--opacity", from: &args).map { try parseDouble($0, label: "--opacity") } ?? 0.5
    let duration = try takeOption("--duration", from: &args).map(parseOverlayDuration) ?? 0
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
        throw WindowToolError.invalidValue(name: "--opacity", expected: "between 0.0 and 1.0", got: "\(opacity)")
    }

    let window = try resolveWindow(bundleId: bundleId, selector: selector)

    killExistingDim()

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    var overlays: [(window: NSWindow, view: DimOverlayView)] = []

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
        overlay.contentView = view
        overlays.append((overlay, view))
    }

    // Moves the cutout to the window's current AX frame on every screen it overlaps.
    let mainScreenHeight = NSScreen.screens[0].frame.height
    func cutOut(_ windowFrame: CGRect) {
        let target = NSRect(x: windowFrame.origin.x, y: mainScreenHeight - windowFrame.maxY,
                            width: windowFrame.width, height: windowFrame.height)
        for (overlay, view) in overlays {
            let frame = overlay.frame
            let cutout = frame.intersects(target) ? target.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y) : nil
            if view.cutoutRect != cutout {
                view.cutoutRect = cutout
                view.needsDisplay = true
            }
        }
    }

    cutOut(CGRect(origin: window.position, size: window.size))
    for (overlay, _) in overlays { overlay.orderFrontRegardless() }

    try "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: dimPIDFile, atomically: true, encoding: .utf8)

    let cleanupPID: @convention(c) (Int32) -> Void = { _ in
        removePIDFileIfOwned(dimPIDFile)
        flushJSONAndExit(0)
    }
    signal(SIGTERM, cleanupPID)
    signal(SIGINT, cleanupPID)

    func dismiss() {
        for (overlay, _) in overlays { overlay.close() }
        removePIDFileIfOwned(dimPIDFile)
        app.stop(nil)
        let dummyEvent = NSEvent.otherEvent(with: .applicationDefined,
                                            location: .zero, modifierFlags: [],
                                            timestamp: 0, windowNumber: 0,
                                            context: nil, subtype: 0,
                                            data1: 0, data2: 0)!
        app.postEvent(dummyEvent, atStart: true)
    }

    // Follow the window like border does; once it closes there is nothing left to dim around.
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
        guard let frame = currentFrame(of: window.element) else {
            timer.invalidate()
            dismiss()
            return
        }
        cutOut(frame)
    }

    if duration > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { dismiss() }
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
        throw WindowToolError.invalidValue(name: "--rect", expected: "four comma-separated fractions: x,y,width,height", got: value)
    }
    let v = try zip(["x", "y", "width", "height"], parts).map { component, part in
        guard let n = Double(part), n.isFinite else {
            throw WindowToolError.invalidValue(name: "--rect", expected: "four comma-separated fractions: x,y,width,height, with \(component) a number", got: value)
        }
        return n
    }
    let eps = 1e-9
    guard v[0] >= 0, v[1] >= 0, v[2] > 0, v[3] > 0, v[0] + v[2] <= 1 + eps, v[1] + v[3] <= 1 + eps else {
        throw WindowToolError.invalidValue(name: "--rect", expected: "fractions of the visible frame with x,y >= 0, width,height > 0, x+width <= 1 and y+height <= 1", got: value)
    }
    return SnapFractions(x: v[0], y: v[1], width: v[2], height: v[3])
}

/// Parses `--grid=<cols>x<rows> --cell=<col>,<row> [--span=<cols>,<rows>]` into fractions of the visible frame.
/// Cells count from 0 at the top left, like window indexes; the span defaults to one cell.
func parseGridFlags(_ args: inout [String]) throws -> SnapFractions? {
    let grid = try takeOption("--grid", from: &args)
    let cell = try takeOption("--cell", from: &args)
    let span = try takeOption("--span", from: &args)
    guard let grid else {
        if cell != nil || span != nil {
            throw WindowToolError.optionRequired(option: "--grid", command: "snap", placeholder: "<cols>x<rows> when --cell or --span is given")
        }
        return nil
    }
    // Splits a flag's value into exactly two whole numbers of at least `min`; otherwise fails naming the flag.
    func pair(_ name: String, _ value: String, separator: Character, min: Int, expected: String) throws -> (Int, Int) {
        let parts = value.split(separator: separator, omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let a = parts[0], let b = parts[1], a >= min, b >= min else {
            throw WindowToolError.invalidValue(name: name, expected: expected, got: value)
        }
        return (a, b)
    }
    let (cols, rows) = try pair("--grid", grid.lowercased(), separator: "x", min: 1, expected: "<cols>x<rows>, whole numbers greater than 0, such as 6x4")
    guard let cell else {
        throw WindowToolError.optionRequired(option: "--cell", command: "snap", placeholder: "<col>,<row> (from 0) when --grid is given")
    }
    let cellExpected = "<col>,<row> counting from 0 at the top left, col at most \(cols - 1) and row at most \(rows - 1) in the \(cols)x\(rows) grid"
    let (col, row) = try pair("--cell", cell, separator: ",", min: 0, expected: cellExpected)
    guard col < cols, row < rows else {
        throw WindowToolError.invalidValue(name: "--cell", expected: cellExpected, got: cell)
    }
    guard let span else {
        return SnapFractions(x: Double(col) / Double(cols), y: Double(row) / Double(rows), width: 1 / Double(cols), height: 1 / Double(rows))
    }
    let spanExpected = "<cols>,<rows> from 1,1 to \(cols - col),\(rows - row), so it fits inside the \(cols)x\(rows) grid from cell \(col),\(row)"
    let (spanCols, spanRows) = try pair("--span", span, separator: ",", min: 1, expected: spanExpected)
    // Subtract rather than add so a huge span cannot overflow.
    guard spanCols <= cols - col, spanRows <= rows - row else {
        throw WindowToolError.invalidValue(name: "--span", expected: spanExpected, got: span)
    }
    return SnapFractions(x: Double(col) / Double(cols), y: Double(row) / Double(rows),
                         width: Double(spanCols) / Double(cols), height: Double(spanRows) / Double(rows))
}

/// Snaps a window to a named screen region, or to `rect` (fractions of the visible frame, from --rect or --grid).
func snapCommand(bundleId: String, selector: WindowSelector, position: SnapPosition?, rect: SnapFractions? = nil) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let bounds = screenBoundsForWindow(window)
    let halfW = bounds.width / 2
    let halfH = bounds.height / 2

    if let f = rect ?? position?.fractions {
        // Round the edges, not the origin and size, so adjacent regions share an edge with no gap.
        // Snapping to 1/1024 first absorbs float error, so an edge computed as x+width rounds like the same edge computed as x.
        func edge(_ v: Double) -> Double { ((v * 1024).rounded() / 1024).rounded() }
        let left = edge(bounds.x + bounds.width * f.x)
        let right = edge(bounds.x + bounds.width * (f.x + f.width))
        let top = edge(bounds.y + bounds.height * f.y)
        let bottom = edge(bounds.y + bounds.height * (f.y + f.height))
        moveWindow(window.element, x: left, y: top)
        resizeWindow(window.element, width: right - left, height: bottom - top)
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
                // Undo finds windows by ID, so a window without one is left where it is
                guard win.windowID != nil else { continue }

                // Check if window center is on the same screen
                let winBounds = screenBoundsForWindow(win)
                guard winBounds.x == bounds.x && winBounds.y == bounds.y &&
                      winBounds.width == bounds.width && winBounds.height == bounds.height else { continue }

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
    }
}

/// Enters macOS fullscreen mode for a window.
func fullscreenCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let result = AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, true as CFTypeRef)
    recordAffectedWindow(window.element, failure: result == .success ? nil : "could not enter fullscreen (AXError \(result.rawValue))")
}

/// Exits macOS fullscreen mode for a window.
func unfullscreenCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    let result = AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, false as CFTypeRef)
    recordAffectedWindow(window.element, failure: result == .success ? nil : "could not exit fullscreen (AXError \(result.rawValue))")
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

/// Minimizes a window. Setting AXMinimized reports success even on a window that cannot be minimized, so a window gets
/// a warning instead unless AXMinimized is settable or its minimize button is enabled (an already minimized one is left as it is).
func minimizeCommand(bundleId: String, selector: WindowSelector) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    var settable: DarwinBoolean = false
    AXUIElementIsAttributeSettable(window.element, kAXMinimizedAttribute as CFString, &settable)
    let buttonEnabled = axElement(window.element, kAXMinimizeButtonAttribute as String).map { axBool($0, kAXEnabledAttribute as String) } ?? false
    guard axBool(window.element, kAXMinimizedAttribute as String) || settable.boolValue || buttonEnabled else {
        recordAffectedWindow(window.element, failure: "cannot be minimized (its minimized state is not settable and it has no enabled minimize button)")
        return
    }
    let result = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, true as CFTypeRef)
    recordAffectedWindow(window.element, failure: result == .success ? nil : "could not minimize (AXError \(result.rawValue))")
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
        axChildren(window.element).contains { axString($0, kAXRoleAttribute as String) == kAXSheetRole as String }
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
            let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            recordAffectedWindow(window, failure: result == .success ? nil : "could not restore (AXError \(result.rawValue))")
            if result == .success { restored += 1 }
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

/// The attributes `tree` reads for each element, fetched with one call per element.
let treeAttributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute,
                      kAXValueAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute]

/// Deepest `--depth` `tree` accepts; it also bounds the recursion if an app reports an element as its own descendant.
let maxTreeDepth = 100

/// An AX value as JSON: strings, finite numbers, booleans and URLs; nil for anything else (points, ranges, elements).
func treeValue(_ value: Any) -> Any? {
    if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return value as? Bool }
    if let string = value as? String { return string.isEmpty ? nil : string }
    if let number = value as? NSNumber { return number.doubleValue.isFinite ? number : nil }
    if let url = value as? URL { return url.absoluteString }
    return nil
}

/// True for a password field, whichever of role or subrole an app reports `AXSecureTextField` in. Neither its value
/// nor any of its descendants' values is ever printed.
func isSecureText(role: String?, subrole: String?) -> Bool {
    role == kAXSecureTextFieldSubrole || subrole == kAXSecureTextFieldSubrole
}

/// `isSecureText` for an element, reading its role and subrole.
func isSecureElement(_ element: AXUIElement) -> Bool {
    isSecureText(role: axString(element, kAXRoleAttribute), subrole: axString(element, kAXSubroleAttribute))
}

/// One element of `tree`: its `path` (child indexes from the window, dot-separated; "" for the window), role, subrole,
/// title, description, identifier, value (strings cut to `maxValue` characters unless it is 0, with `value_truncated`;
/// a secure text field and everything inside it get `secure: true` and no value; pass `insideSecure` when `element`
/// has a secure ancestor),
/// frame (x, y, width, height) and actions, then its children for `depth` more levels. Missing and empty attributes are
/// left out. When `depth` stops the walk, an element with children gets `children_omitted` (their number) instead of `children`.
func treeNode(_ element: AXUIElement, path: String = "", depth: Int, maxValue: Int, insideSecure: Bool = false) -> [String: Any] {
    var valuesRef: CFArray?
    AXUIElementCopyMultipleAttributeValues(element, treeAttributes as CFArray, [], &valuesRef)
    // The values come back in treeAttributes order.
    let attributes = Dictionary(uniqueKeysWithValues: zip(treeAttributes, valuesRef as? [Any] ?? []))

    var node: [String: Any] = ["path": path]
    for (key, name) in [("role", kAXRoleAttribute), ("subrole", kAXSubroleAttribute), ("title", kAXTitleAttribute),
                        ("description", kAXDescriptionAttribute), ("identifier", kAXIdentifierAttribute)] {
        if let string = attributes[name] as? String, !string.isEmpty { node[key] = string }
    }
    // The batch read fetched a secure field's value too; it is dropped here and never stored or printed.
    let secure = insideSecure || isSecureText(role: node["role"] as? String, subrole: node["subrole"] as? String)
    if secure {
        node["secure"] = true
    } else if let value = attributes[kAXValueAttribute].flatMap(treeValue) {
        if let string = value as? String, maxValue > 0, string.count > maxValue {
            node["value"] = String(string.prefix(maxValue))
            node["value_truncated"] = true
        } else {
            node["value"] = value
        }
    }
    if let position = axValue(attributes[kAXPositionAttribute], .cgPoint, CGPoint.zero),
       let size = axValue(attributes[kAXSizeAttribute], .cgSize, CGSize.zero) {
        node["x"] = roundedInt(position.x)
        node["y"] = roundedInt(position.y)
        node["width"] = roundedInt(size.width)
        node["height"] = roundedInt(size.height)
    }
    var actionsRef: CFArray?
    AXUIElementCopyActionNames(element, &actionsRef)
    node["actions"] = actionsRef as? [String] ?? []

    let children = attributes[kAXChildrenAttribute] as? [AXUIElement] ?? []
    if !children.isEmpty {
        if depth > 0 {
            node["children"] = children.enumerated().map { index, child in
                treeNode(child, path: path.isEmpty ? "\(index)" : "\(path).\(index)", depth: depth - 1, maxValue: maxValue, insideSecure: secure)
            }
        } else {
            node["children_omitted"] = children.count
        }
    }
    return node
}

/// Escapes a string for one line of text output, shared by `tree` and `text`: backslash, quote, every control character,
/// U+2028/U+2029 and the bidi embedding, override and isolate controls, so a value cannot break the line, send terminal escape sequences or
/// reorder the rest of the line. `text` passes `quotes: false`, as it prints values unquoted, and for `--raw` `raw: true`,
/// which keeps line breaks, tabs, quotes and backslashes as they are.
func treeEscape(_ string: String, quotes: Bool = true, raw: Bool = false) -> String {
    var escaped = ""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\n" where raw, "\t" where raw, "\\" where raw, "\"" where raw: escaped.unicodeScalars.append(scalar)
        case "\\": escaped += "\\\\"
        case "\"" where quotes: escaped += "\\\""
        case "\n": escaped += "\\n"
        case "\r": escaped += "\\r"
        case "\t": escaped += "\\t"
        case _ where scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || (0x2028...0x202E).contains(scalar.value) ||
                    (0x2066...0x2069).contains(scalar.value):
            escaped += "\\u{\(String(scalar.value, radix: 16))}"
        default: escaped.unicodeScalars.append(scalar)
        }
    }
    return escaped
}

/// A string for one line of `tree` text output: cut to 80 characters, then escaped and quoted.
func treeDisplayString(_ string: String) -> String {
    "\"" + treeEscape(string.count > 80 ? string.prefix(79) + "…" : string) + "\""
}

/// An action name for `tree` text output: custom actions show only their name.
func treeDisplayAction(_ action: String) -> String {
    treeEscape(actionName(action))
}

/// Prints a `treeNode` and its children as indented lines, two spaces per level, each but the window's starting
/// with its `[path]`. The root may carry `window_id` (added by `treeCommand`). Returns whether any element had children cut off by --depth.
@discardableResult
func printTreeNode(_ node: [String: Any], level: Int = 0) -> Bool {
    var parts = [[node["role"], node["subrole"]].compactMap { ($0 as? String).map { treeEscape($0) } }.joined(separator: ":")]
    if parts[0].isEmpty { parts[0] = "(no role)" }
    if let path = node["path"] as? String, !path.isEmpty { parts[0] = "[\(path)] " + parts[0] }
    if let windowID = node["window_id"] { parts.append("window_id=\(windowID)") }
    for key in ["title", "description", "identifier"] {
        if let string = node[key] as? String { parts.append("\(key)=\(treeDisplayString(string))") }
    }
    if let value = node["value"] {
        // A value cut by --max-value gets "…", as one cut for display does.
        let truncated = node["value_truncated"] as? Bool == true
        parts.append("value=" + ((value as? String).map { treeDisplayString(truncated ? $0 + "…" : $0) } ?? "\(value)"))
    }
    if node["secure"] as? Bool == true { parts.append("secure") }
    if let x = node["x"], let y = node["y"], let width = node["width"], let height = node["height"] {
        parts.append("frame=\(x),\(y) \(width)x\(height)")
    }
    if let actions = node["actions"] as? [String], !actions.isEmpty {
        parts.append("actions=" + actions.map(treeDisplayAction).joined(separator: ","))
    }
    var cutOff = false
    if let omitted = node["children_omitted"] as? Int {
        parts.append("children_omitted=\(omitted)")
        cutOff = true
    }
    print(String(repeating: "  ", count: level) + parts.joined(separator: "  "))
    for child in node["children"] as? [[String: Any]] ?? [] {
        cutOff = printTreeNode(child, level: level + 1) || cutOff
    }
    return cutOff
}

/// Prints a window's accessibility element tree, `depth` levels below the window. The root also gets `window_id`.
func treeCommand(bundleId: String, selector: WindowSelector, depth: Int, maxValue: Int) throws {
    let w = try resolveWindow(bundleId: bundleId, selector: selector)
    var root = treeNode(w.element, depth: depth, maxValue: maxValue)
    if let windowID = w.windowID { root["window_id"] = Int(windowID) }
    if config.jsonOutput {
        printJSON(root)
    } else if printTreeNode(root) {
        fflush(stdout)
        fputs("Some elements have children_omitted: raise --depth to show them.\n", stderr)
    }
}

// MARK: - Element Paths

// A path addresses one element by its child indexes from the window, as `tree` prints it ("0.2.1"; "" is the window).
// These helpers are shared by every command that takes a path: `text --path` and `press --path`.

/// An action's name. AppKit custom actions are "Name:<name>\nTarget:…\nSelector:…"; other actions are their own name.
func actionName(_ action: String) -> String {
    guard action.hasPrefix("Name:") else { return action }
    return String(action.dropFirst(5).prefix { !$0.isNewline })
}

/// Reads an AX attribute that holds an element (a parent, the focused element), or nil.
func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let ref,
          CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
    return (ref as! AXUIElement)
}

/// An element's children in `kAXChildrenAttribute` order, the order `tree` numbers them in. `treeNode` reads the same
/// attribute in its one batch call per element instead, so it does not use this.
func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref)
    return ref as? [AXUIElement] ?? []
}

/// The element at a `tree` path in `window`. Throws `invalidValue` for a malformed path (only canonical whole numbers,
/// so `01` and `+1` fail) and `noElementAtPath` for an index past the end. `insideSecure` is true when an element above
/// the target (not the target itself) is a secure text field, for `treeNode`'s `insideSecure`.
func elementAtPath(_ path: String, in window: WindowInfo) throws -> (element: AXUIElement, insideSecure: Bool) {
    var element = window.element
    var insideSecure = false
    var walked: [Substring] = []
    for component in path.isEmpty ? [] : path.split(separator: ".", omittingEmptySubsequences: false) {
        guard let index = Int(component), index >= 0, String(index) == component else {
            throw WindowToolError.invalidValue(name: "--path", expected: "child indexes joined with '.' as 'tree' prints them, such as 0.2.1 (\"\" for the window)", got: path)
        }
        let children = axChildren(element)
        guard index < children.count else {
            throw WindowToolError.noElementAtPath(path: path, parent: walked.joined(separator: "."), count: children.count, windowID: window.windowID)
        }
        insideSecure = insideSecure || isSecureElement(element)
        element = children[index]
        walked.append(component)
    }
    return (element, insideSecure)
}

/// The `tree` path of `element` in `window`, found by walking up its parents, or nil when that walk does not reach the
/// window. `insideSecure` is true when one of those parents is a secure text field, as in `elementAtPath`.
func pathOfElement(_ element: AXUIElement, in window: AXUIElement) -> (path: String, insideSecure: Bool)? {
    var indexes: [Int] = []
    var insideSecure = false
    var current = element
    while !CFEqual(current, window) {
        guard indexes.count < maxTreeDepth, let parent = axElement(current, kAXParentAttribute),
              let index = axChildren(parent).firstIndex(where: { CFEqual($0, current) }) else { return nil }
        indexes.insert(index, at: 0)
        current = parent
        insideSecure = insideSecure || isSecureElement(parent)
    }
    return (indexes.map(String.init).joined(separator: "."), insideSecure)
}

// MARK: - Text Command

/// Roles whose value is text in the window: labels and text inputs. Secure text fields never count (see `isSecureText`).
let textRoles: Set<String> = [kAXStaticTextRole, kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

/// The string values of a `treeNode` and its descendants that have a text role, in tree order, as `path`/`role`/`value`
/// objects (plus `value_truncated`). An element whose frame is empty or does not overlap `frame` (the window's) is left
/// out, but its children are still read. Secure nodes, which `treeNode` marks along with all their descendants, are skipped.
func visibleTexts(_ node: [String: Any], in frame: CGRect) -> [[String: Any]] {
    if node["secure"] as? Bool == true { return [] }
    var texts: [[String: Any]] = []
    if let role = node["role"] as? String, textRoles.contains(role), let value = node["value"] as? String {
        var inside = true
        if let x = node["x"] as? Int, let y = node["y"] as? Int, let width = node["width"] as? Int, let height = node["height"] as? Int {
            inside = width > 0 && height > 0 && CGRect(x: x, y: y, width: width, height: height).intersects(frame)
        }
        if inside {
            var text: [String: Any] = ["path": node["path"] ?? "", "role": role, "value": value]
            if node["value_truncated"] != nil { text["value_truncated"] = true }
            texts.append(text)
        }
    }
    return texts + (node["children"] as? [[String: Any]] ?? []).flatMap { visibleTexts($0, in: frame) }
}

/// The app's focused element as `path`, `role`, `value` (a string, number or boolean, cut to `maxValue`), `value_truncated`
/// and `secure`, when it is in `window` at or below `path`, or nil. Keyboard focus belongs to the app, not the window,
/// so when another window of the same app holds it this returns nil. The node comes from `treeNode`, so a secure
/// text field, or any element inside one, gets `secure: true` and no value.
func focusedElementJSON(in window: AXUIElement, under path: String, maxValue: Int) -> [String: Any]? {
    var pid: pid_t = 0
    guard AXUIElementGetPid(window, &pid) == .success,
          let element = axElement(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
          let (focusedPath, insideSecure) = pathOfElement(element, in: window),
          path.isEmpty || focusedPath == path || focusedPath.hasPrefix(path + ".") else { return nil }
    return treeNode(element, path: focusedPath, depth: 0, maxValue: maxValue, insideSecure: insideSecure)
        .filter { ["path", "role", "value", "value_truncated", "secure"].contains($0.key) }
}

/// A value for `text` output: escaped onto one line, or with `raw` only terminal controls escaped; "…" when cut by `--max-value`.
func textLine(_ value: Any, truncated: Bool, raw: Bool) -> String {
    guard let string = value as? String else { return "\(value)" }
    return treeEscape(truncated ? string + "…" : string, quotes: false, raw: raw)
}

/// Prints the text inside a window: the values of its labels and text inputs whose frames overlap the window's, at or
/// below `path`, one per line, and under `--json` also the focused element. With `focusedOnly`, prints only the focused
/// element's value (nothing when it has none, such as a secure field) and throws `noFocusedElement` when the window
/// (or `path`) holds no keyboard focus.
func textCommand(bundleId: String, selector: WindowSelector, path: String, focusedOnly: Bool, raw: Bool, maxValue: Int) throws {
    let w = try resolveWindow(bundleId: bundleId, selector: selector)
    let (start, insideSecure) = try elementAtPath(path, in: w)
    let focused = focusedOnly || config.jsonOutput ? focusedElementJSON(in: w.element, under: path, maxValue: maxValue) : nil
    if focusedOnly {
        guard let focused else { throw WindowToolError.noFocusedElement(windowID: w.windowID, path: path) }
        if config.jsonOutput {
            printJSON(focused)
        } else if let value = focused["value"] {
            print(textLine(value, truncated: focused["value_truncated"] != nil, raw: raw))
        }
        return
    }
    let texts = visibleTexts(treeNode(start, path: path, depth: maxTreeDepth, maxValue: maxValue, insideSecure: insideSecure), in: CGRect(origin: w.position, size: w.size))
    if config.jsonOutput {
        var result: [String: Any] = ["path": path, "texts": texts, "focused": focused ?? NSNull()]
        if let windowID = w.windowID { result["window_id"] = Int(windowID) }
        printJSON(result)
    } else {
        for text in texts {
            print(textLine(text["value"] ?? "", truncated: text["value_truncated"] != nil, raw: raw))
        }
    }
}

// MARK: - Press Command

/// An element `press` matched or acted on: its `tree` path, role and title.
typealias ElementMatch = (path: String, role: String?, title: String?)

/// "[0] AXButton title="Save"" for `press` messages, or "the window" and its title for the root.
func describeElement(_ match: ElementMatch) -> String {
    (match.path.isEmpty ? "the window" : "[\(match.path)] \(treeEscape(match.role ?? "(no role)"))") +
        (match.title.map { " title=\(treeDisplayString($0))" } ?? "")
}

/// An `ElementMatch` as JSON; `role` and `title` are left out when absent.
func elementMatchJSON(_ match: ElementMatch) -> [String: Any] {
    var json: [String: Any] = ["path": match.path]
    json["role"] = match.role
    json["title"] = match.title
    return json
}

/// "with role AXButton and title "Save"" for `press` errors.
func elementQuery(role: String?, title: String?) -> String {
    let parts = [role.map { "role \(treeEscape($0))" }, title.map { "title \(treeDisplayString($0))" }].compactMap { $0 }
    return "with " + parts.joined(separator: " and ")
}

/// The `treeNode`s at or below `node` whose role is `role` and whose title is `title` (ignoring case), each nil to
/// match any, in tree order. Secure nodes, and everything inside them, never match.
func matchingElements(_ node: [String: Any], role: String?, title: String?) -> [ElementMatch] {
    if node["secure"] as? Bool == true { return [] }
    let nodeRole = node["role"] as? String, nodeTitle = node["title"] as? String
    let matches = (role == nil || nodeRole == role) &&
        (title.map { nodeTitle?.caseInsensitiveCompare($0) == .orderedSame } ?? true)
    let match: [ElementMatch] = matches ? [(node["path"] as? String ?? "", nodeRole, nodeTitle)] : []
    return match + (node["children"] as? [[String: Any]] ?? []).flatMap { matchingElements($0, role: role, title: title) }
}

/// Performs an accessibility action (AXPress by default) on one element of a window: the one at `path`, or with
/// `role`/`title` the only element at or below `path` that matches. `action` is a raw action string from `tree --json`
/// or a custom action's name. Never acts on a password field or anything inside one. An app that does not answer in
/// time (a button that opens a modal dialog, or a hung app) gives a warning and `confirmed: false`, not an error.
func pressCommand(bundleId: String, selector: WindowSelector, path: String, role: String?, title: String?, action: String) throws {
    let w = try resolveWindow(bundleId: bundleId, selector: selector)
    var (element, insideSecure) = try elementAtPath(path, in: w)
    if insideSecure || isSecureElement(element) { throw WindowToolError.secureElement(path: path, windowID: w.windowID) }
    var targetPath = path
    if role != nil || title != nil {
        let matches = matchingElements(treeNode(element, path: path, depth: maxTreeDepth, maxValue: 1), role: role, title: title)
        guard let match = matches.first else {
            throw WindowToolError.noMatchingElement(role: role, title: title, path: path, windowID: w.windowID)
        }
        guard matches.count == 1 else {
            throw WindowToolError.ambiguousElement(role: role, title: title, path: path, matches: matches, windowID: w.windowID)
        }
        // The UI can change between the walk and this lookup, so the element found again is checked again.
        (element, insideSecure) = try elementAtPath(match.path, in: w)
        if insideSecure || isSecureElement(element) { throw WindowToolError.secureElement(path: match.path, windowID: w.windowID) }
        targetPath = match.path
    }
    let target: ElementMatch = (targetPath, axString(element, kAXRoleAttribute), axString(element, kAXTitleAttribute))

    var actionsRef: CFArray?
    AXUIElementCopyActionNames(element, &actionsRef)
    let actions = actionsRef as? [String] ?? []
    guard let rawAction = actions.first(where: { $0 == action || actionName($0) == action }) else {
        throw WindowToolError.actionNotSupported(action: action, path: target.path, actions: actions, windowID: w.windowID)
    }
    let description = "\(treeEscape(actionName(rawAction))) on \(describeElement(target))"
    let result = AXUIElementPerformAction(element, rawAction as CFString)
    switch result {
    case .success:
        break
    case .cannotComplete:
        commandWarnings.append("the app did not confirm \(description) (AXError \(result.rawValue)); it may have run it (a button that opens a dialog) or the app may be hung, so read the window again to check")
    default:
        throw WindowToolError.operationFailed("Could not perform \(description) (AXError \(result.rawValue))")
    }
    recordAffectedWindow(w.element)
    commandResultFields["element"] = elementMatchJSON(target).merging(["action": rawAction, "confirmed": result == .success]) { $1 }
    printStatus("Performed \(description)")
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
    let fps = try takeOption("--fps", from: &args).map(parseFps) ?? 30
    let duration = try takeOption("--duration", from: &args).map { try parsePositiveDouble($0, label: "--duration") }
    let countdown = !takeFlag("--no-countdown", from: &args)
    let border = !takeFlag("--no-border", from: &args)
    return (output, fps, duration, countdown, border)
}

/// The image in a ScreenCaptureKit sample, or nil when the sample holds no new frame (SCK also sends idle and blank samples).
func completeFrame(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
    guard sampleBuffer.isValid,
          let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
          let statusValue = attachments.first?[.status] as? Int,
          SCFrameStatus(rawValue: statusValue) == .complete else {
        return nil
    }
    return CMSampleBufferGetImageBuffer(sampleBuffer)
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
        guard type == .screen, let pixelBuffer = completeFrame(sampleBuffer) else { return }

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

// MARK: - Pip Command

enum PipCorner: String, CaseIterable {
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
}

func parsePipFlags(_ args: inout [String]) throws -> (scale: Double, corner: PipCorner, fps: Int, duration: Double?) {
    let scale = try takeOption("--scale", from: &args).map { value in
        guard let scale = Double(value), scale > 0 && scale <= 1 else {
            throw WindowToolError.invalidValue(name: "--scale", expected: "a number greater than 0 and at most 1", got: value)
        }
        return scale
    } ?? 0.3
    let corner = try takeOption("--position", from: &args).map { value in
        guard let corner = PipCorner(rawValue: value) else {
            throw WindowToolError.unknownChoice(kind: "position", value: value, choices: PipCorner.allCases.map(\.rawValue))
        }
        return corner
    } ?? .bottomRight
    let fps = try takeOption("--fps", from: &args).map(parseFps) ?? 10
    let duration = try takeOption("--duration", from: &args).map { try parsePositiveDouble($0, label: "--duration") }
    return (scale, corner, fps, duration)
}

/// The thumbnail's frame in Cocoa coordinates: the window's size times `scale`, shrunk further when needed to fit
/// `visible`, placed `margin` points in from `corner`.
func pipFrame(windowSize: CGSize, scale: Double, corner: PipCorner, visible: NSRect, margin: CGFloat = 20) -> NSRect {
    let fit = min(CGFloat(scale), (visible.width - 2 * margin) / windowSize.width, (visible.height - 2 * margin) / windowSize.height)
    let width = max(1, (windowSize.width * fit).rounded())
    let height = max(1, (windowSize.height * fit).rounded())
    let x = corner == .topLeft || corner == .bottomLeft ? visible.minX + margin : visible.maxX - margin - width
    let y = corner == .bottomLeft || corner == .bottomRight ? visible.minY + margin : visible.maxY - margin - height
    return NSRect(x: x, y: y, width: width, height: height)
}

/// Shows each new frame of the captured window in `layer`, and passes on the error of a stream that stops by itself.
class PipStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let layer: CALayer
    let onStop: (any Error) -> Void

    init(layer: CALayer, onStop: @escaping (any Error) -> Void) {
        self.layer = layer
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = completeFrame(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        layer.contents = surface
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { self.onStop(error) }
    }
}

/// Shows a live, scaled copy of a window in an always-on-top thumbnail. Blocks until Ctrl-C, until the window
/// closes, or until `duration` seconds pass. Its lifecycle mirrors `recordCommand`: an SCStream feeding an
/// NSApplication run loop that signal sources stop.
func pipCommand(bundleId: String, selector: WindowSelector, scale: Double, corner: PipCorner, fps: Int, duration: Double?) throws {
    let window = try resolveWindow(bundleId: bundleId, selector: selector)
    guard let windowID = window.windowID else {
        throw WindowToolError.operationFailed("Cannot capture window — no window ID available")
    }
    guard CGPreflightScreenCaptureAccess() else {
        throw WindowToolError.screenRecordingNotEnabled
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let frame = pipFrame(windowSize: window.size, scale: scale, corner: corner, visible: screen.visibleFrame)
    let thumbnail = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    thumbnail.backgroundColor = .black
    thumbnail.level = .floating
    thumbnail.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    thumbnail.isMovableByWindowBackground = true
    let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    view.layer?.contentsGravity = .resizeAspect
    thumbnail.contentView = view
    thumbnail.orderFrontRegardless()

    // Set by the first stop, so a second stop, a late stream start or a timer cannot stop a later command in the chain.
    var finished = false
    var stopError: (any Error)?
    func stop(_ error: (any Error)? = nil) {
        guard !finished else { return }
        finished = true
        // A capture that ends because its window closed is the normal way out, not a failure.
        if let error, stopError == nil, currentFrame(of: window.element) != nil {
            stopError = error
        }
        // app.stop only takes effect after the run loop handles an event, so post one to wake it now.
        app.stop(nil)
        let event = NSEvent.otherEvent(with: .applicationDefined,
            location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        app.postEvent(event, atStart: true)
    }

    let output = PipStreamOutput(layer: view.layer!, onStop: { stop($0) })
    let streamConfig = SCStreamConfiguration()
    streamConfig.width = Int(frame.width * screen.backingScaleFactor)
    streamConfig.height = Int(frame.height * screen.backingScaleFactor)
    streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
    streamConfig.showsCursor = false
    streamConfig.queueDepth = 3
    streamConfig.scalesToFit = true
    var stream: SCStream?
    Task { @MainActor in
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw WindowToolError.noWindowMatchingID(windowID)
            }
            let started = SCStream(filter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: streamConfig, delegate: output)
            try started.addStreamOutput(output, type: .screen, sampleHandlerQueue: .main)
            try await started.startCapture()
            if finished {
                try? await started.stopCapture()
            } else {
                stream = started
                fputs("Showing window \(windowID) in a thumbnail; drag it to move it, press Ctrl-C to close it\n", stderr)
            }
        } catch {
            stop(error)
        }
    }

    let signalSources = [SIGINT, SIGTERM].map { signalNumber in
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { stop() }
        source.resume()
        return source
    }
    let closeCheck = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        if currentFrame(of: window.element) == nil { stop() }
    }
    let durationTimer = duration.map { Timer.scheduledTimer(withTimeInterval: $0, repeats: false) { _ in stop() } }

    app.run()

    closeCheck.invalidate()
    durationTimer?.invalidate()
    stream?.stopCapture()
    thumbnail.orderOut(nil)
    for source in signalSources { source.cancel() }
    signal(SIGINT, SIG_DFL)
    signal(SIGTERM, SIG_DFL)
    if let error = stopError as? SCStreamError, error.code == .userDeclined {
        throw WindowToolError.screenRecordingNotEnabled
    }
    if let stopError { throw stopError }
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

/// Named layouts (`save-layout coding`) are saved here as `<name>.json`, under `$HOME` like other command-line tools' config.
let layoutsDirectory = ((ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()) as NSString).appendingPathComponent(".config/window-tool/layouts")

/// How long `restore-layout --launch` waits for the apps it opened to show their windows.
let layoutLaunchTimeout: TimeInterval = 10

/// A frame as fractions of a display's visible frame (0 to 1 from its top-left corner), so a layout survives a resolution change.
struct FractionalFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    /// Rounded to 6 decimal places: readable in the file, and well under a point on any display.
    init(_ rect: CGRect, in visible: CGRect) {
        let round6 = { (v: CGFloat) in (Double(v) * 1e6).rounded() / 1e6 }
        x = round6((rect.minX - visible.minX) / visible.width)
        y = round6((rect.minY - visible.minY) / visible.height)
        width = round6(rect.width / visible.width)
        height = round6(rect.height / visible.height)
    }

    func rect(in visible: CGRect) -> CGRect {
        CGRect(x: visible.minX + x * visible.width, y: visible.minY + y * visible.height,
               width: width * visible.width, height: height * visible.height)
    }
}

struct WindowSnapshot: Codable {
    /// Absent in layouts saved before layouts covered every app; the layout's top-level `bundle_id` applies.
    let bundleId: String?
    let index: Int
    /// Absent in layouts saved before window IDs were recorded, and for windows without one.
    let windowID: Int?
    let title: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    /// The display holding the window's center (its `uuid` in `screens`) and the frame as fractions of that display's
    /// visible frame. Absent in older layouts and for a window on no display; those restore to x, y, width, height.
    let screenUUID: String?
    let fraction: FractionalFrame?

    enum CodingKeys: String, CodingKey {
        case index, title, x, y, width, height, fraction
        case bundleId = "bundle_id"
        case windowID = "window_id"
        case screenUUID = "screen_uuid"
    }
}

struct WindowLayout: Codable {
    /// Set when the layout was saved with --app, as every layout saved before layouts covered all apps was.
    let bundleId: String?
    let windows: [WindowSnapshot]

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case windows
    }
}

/// True when a `save-layout`/`restore-layout` argument names a layout; one with a `/` or ending in `.json` is a file path.
func isLayoutName(_ arg: String) -> Bool {
    !arg.contains("/") && !arg.hasSuffix(".json")
}

/// The file for a layout argument: a name is `<layoutsDirectory>/<name>.json`, a path is used as given.
func layoutPath(_ arg: String) throws -> String {
    guard isLayoutName(arg) else { return arg }
    guard !arg.isEmpty, !arg.hasPrefix("."), arg.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else {
        throw WindowToolError.invalidValue(name: "layout name", expected: "letters, digits, '.', '_' and '-', not starting with '.' (or a file path containing '/' or ending in .json)", got: arg)
    }
    return (layoutsDirectory as NSString).appendingPathComponent(arg + ".json")
}

/// Saves the windows of every running app, or only of `bundleId`, as a named layout or to a file. Each window keeps its
/// app, index, window ID, title and frame, plus its display's UUID and the frame as fractions of that display.
/// Like `list`, untitled windows without a window ID are left out: nothing could match them again.
func saveLayoutCommand(bundleId: String?, target: String) throws {
    let filePath = try layoutPath(target)
    let apps: [(bundleId: String, element: AXUIElement)]
    if let bundleId {
        apps = [(bundleId, try requireApp(bundleId))]
    } else {
        var seen = Set<String>()
        apps = NSWorkspace.shared.runningApplications.compactMap { app -> (bundleId: String, element: AXUIElement)? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return (id, AXUIElementCreateApplication(app.processIdentifier))
        }
    }
    let screens = NSScreen.screens
    let frames = screens.map { cocoaToAX(rect: $0.frame) }
    let visibleFrames = screens.map { cocoaToAX(rect: $0.visibleFrame) }
    var snapshots: [WindowSnapshot] = []
    for app in apps {
        for w in getWindows(appElement: app.element) where !(w.title.isEmpty && w.windowID == nil) {
            let rect = CGRect(origin: w.position, size: w.size)
            var uuid: String?
            var fraction: FractionalFrame?
            if let screen = frames.firstIndex(where: { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) }), let id = displayUUID(screens[screen]) {
                uuid = id
                fraction = FractionalFrame(rect, in: visibleFrames[screen])
            }
            snapshots.append(WindowSnapshot(bundleId: app.bundleId, index: w.id, windowID: w.windowID.map { Int($0) }, title: w.title,
                                            x: roundedInt(rect.minX), y: roundedInt(rect.minY),
                                            width: roundedInt(rect.width), height: roundedInt(rect.height),
                                            screenUUID: uuid, fraction: fraction))
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(WindowLayout(bundleId: bundleId, windows: snapshots))
    if isLayoutName(target) {
        try FileManager.default.createDirectory(atPath: layoutsDirectory, withIntermediateDirectories: true)
    }
    try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    if config.jsonOutput, var saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        saved["path"] = filePath
        printJSON(saved)
    }
    printStatus("Saved \(snapshots.count) window(s) to \(filePath)")
}

/// Pairs saved windows with an app's current ones by window ID, then title, then index; each current window is used at
/// most once. Returns, for each position in `saved` that matched, the window and how it matched (`id`, `title` or `index`).
func matchLayoutWindows(_ saved: [WindowSnapshot], to current: [WindowInfo]) -> [Int: (window: WindowInfo, by: String)] {
    // WindowInfo.id is the position in getWindows, unique here (it is -1 only for windows outside that list).
    var claimed = Set<Int>()
    var matches: [Int: (window: WindowInfo, by: String)] = [:]
    let strategies: [(name: String, matches: (WindowSnapshot, WindowInfo) -> Bool)] = [
        ("id", { saved, current in saved.windowID != nil && saved.windowID == current.windowID.map { Int($0) } }),
        // Untitled windows would all match each other, so an empty title never matches.
        ("title", { saved, current in !saved.title.isEmpty && saved.title == current.title }),
        // Last resort: whatever window now sits at the saved index, which may be an unrelated one.
        ("index", { saved, current in saved.index == current.id }),
    ]
    for strategy in strategies {
        for (position, window) in saved.enumerated() where matches[position] == nil {
            if let match = current.first(where: { !claimed.contains($0.id) && strategy.matches(window, $0) }) {
                claimed.insert(match.id)
                matches[position] = (match, strategy.name)
            }
        }
    }
    return matches
}

/// Opens each app in `bundleIds` without waiting, then polls until every one is running with at least `windowCounts[id]`
/// windows or `layoutLaunchTimeout` passes. Returns the apps running by then; each one that is missing or short of windows
/// at the deadline, or not installed, gets a warning.
func launchApps(_ bundleIds: [String], windowCounts: [String: Int]) -> [String: AXUIElement] {
    var pending: [String] = []
    for bundleId in bundleIds {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            commandWarnings.append("\(bundleId) is not installed; its windows were skipped")
            continue
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        pending.append(bundleId)
    }
    var opened: [String: AXUIElement] = [:]
    let deadline = Date().addingTimeInterval(layoutLaunchTimeout)
    while true {
        for bundleId in pending where opened[bundleId] == nil {
            opened[bundleId] = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
                .map { AXUIElementCreateApplication($0.processIdentifier) }
        }
        let waiting = pending.filter { bundleId in
            opened[bundleId].map { getWindows(appElement: $0).count < windowCounts[bundleId, default: 0] } ?? true
        }
        if waiting.isEmpty { break }
        if Date() >= deadline {
            for bundleId in waiting {
                if let app = opened[bundleId] {
                    commandWarnings.append("\(bundleId) showed \(getWindows(appElement: app).count) of \(windowCounts[bundleId, default: 0]) saved window(s) within \(formatSeconds(layoutLaunchTimeout)); restoring the ones it has")
                } else {
                    commandWarnings.append("\(bundleId) did not open within \(formatSeconds(layoutLaunchTimeout)); its windows were skipped")
                }
            }
            break
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return opened
}

/// One saved window in a restore: the window it matched (nil when it will not move) and the frame it goes to.
struct LayoutPlanEntry {
    let bundleId: String
    let title: String
    /// `id`, `title` or `index` for a matched window; `none` when nothing matched, `not_running` when the app is not
    /// running, and `launch` when `--launch` would open the app (dry run only).
    let match: String
    let window: WindowInfo?
    let frame: CGRect

    var willMove: Bool { window != nil }

    var json: [String: Any] {
        ["bundle_id": bundleId, "title": title, "match": match, "will_move": willMove,
         "window_id": window?.windowID.map { Int($0) as Any } ?? NSNull(),
         "x": roundedInt(frame.minX), "y": roundedInt(frame.minY), "width": roundedInt(frame.width), "height": roundedInt(frame.height)]
    }
}

/// Restores a layout (a name or a file from `save-layout`), matching each app's saved windows with `matchLayoutWindows`.
/// A window saved with a display UUID goes to the same fractions of that display's visible frame, or of the primary
/// display when that display is not connected; older layouts restore the absolute frame. Apps that are not running are
/// skipped with a warning unless `launch` opens them, and when none of the layout's apps is running a real restore fails
/// with `app_not_found`. Unmatched saved windows are skipped and reported as warnings; the `--json` result adds
/// `restored` and `total`. `dryRun` prints the plan instead of moving anything (and does not launch apps).
func restoreLayoutCommand(target: String, launch: Bool, dryRun: Bool) throws {
    let filePath = try layoutPath(target)
    guard FileManager.default.fileExists(atPath: filePath) else {
        let hint = isLayoutName(target) ? "Run 'window-tool layouts' to list saved layouts."
            : !target.contains("/") ? "To restore a saved layout by name, drop the extension: 'restore-layout \(target.dropLast(".json".count))'." : nil
        throw WindowToolError.fileNotFound(filePath, hint: hint)
    }
    guard let data = FileManager.default.contents(atPath: filePath), let layout = try? JSONDecoder().decode(WindowLayout.self, from: data) else {
        throw WindowToolError.operationFailed("\(filePath) is not a window-tool layout (save one with 'window-tool save-layout')")
    }
    // The saved windows grouped by app, apps in the order they first appear.
    var appOrder: [String] = []
    var savedByApp: [String: [WindowSnapshot]] = [:]
    for saved in layout.windows {
        guard let bundleId = saved.bundleId ?? layout.bundleId else {
            throw WindowToolError.operationFailed("Layout \(filePath) has a window with no bundle_id: '\(saved.title)'")
        }
        if savedByApp[bundleId] == nil { appOrder.append(bundleId) }
        savedByApp[bundleId, default: []].append(saved)
    }
    var apps: [String: AXUIElement] = [:]
    for bundleId in appOrder { apps[bundleId] = getAppElement(bundleId: bundleId) }
    let notRunning = appOrder.filter { apps[$0] == nil }
    if !launch, !dryRun, !appOrder.isEmpty, notRunning.count == appOrder.count {
        throw WindowToolError.appNotFound(notRunning.joined(separator: ", "))
    }
    if launch && !dryRun {
        apps.merge(launchApps(notRunning, windowCounts: savedByApp.mapValues(\.count))) { $1 }
    }

    let screens = NSScreen.screens
    let uuids = screens.map(displayUUID)
    let visibleFrames = screens.map { cocoaToAX(rect: $0.visibleFrame) }
    var missingDisplays = Set<String>()
    func targetFrame(_ saved: WindowSnapshot) -> CGRect {
        guard let uuid = saved.screenUUID, let fraction = saved.fraction else {
            return CGRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
        }
        if let screen = uuids.firstIndex(of: uuid) { return fraction.rect(in: visibleFrames[screen]) }
        if missingDisplays.insert(uuid).inserted {
            commandWarnings.append("display \(uuid) is not connected; its windows go to the primary display")
        }
        return fraction.rect(in: visibleFrames[0])
    }

    var plan: [LayoutPlanEntry] = []
    for bundleId in appOrder {
        let saved = savedByApp[bundleId, default: []]
        guard let app = apps[bundleId] else {
            if !launch {
                commandWarnings.append("\(bundleId) is not running; skipped \(saved.count) window(s). Pass --launch to open it.")
            }
            // After a real --launch, an app still missing here failed to open and already has a warning.
            plan += saved.map { LayoutPlanEntry(bundleId: bundleId, title: $0.title, match: launch && dryRun ? "launch" : "not_running", window: nil, frame: targetFrame($0)) }
            continue
        }
        let matches = matchLayoutWindows(saved, to: getWindows(appElement: app))
        for (position, window) in saved.enumerated() {
            let match = matches[position]
            if match == nil {
                let id = window.windowID.map { ", id=\($0)" } ?? ""
                commandWarnings.append("no \(bundleId) window matches saved '\(window.title)' (index \(window.index)\(id)); skipped")
            }
            plan.append(LayoutPlanEntry(bundleId: bundleId, title: window.title, match: match?.by ?? "none", window: match?.window, frame: targetFrame(window)))
        }
    }

    if dryRun {
        if config.jsonOutput {
            printJSON(["plan": plan.map(\.json), "warnings": commandWarnings] as [String: Any])
        } else {
            print("APP\tMATCH\tWID\tPOSITION\tSIZE\tTITLE")
            for entry in plan {
                let wid = entry.window?.windowID.map { "\($0)" } ?? "-"
                print("\(entry.bundleId)\t\(entry.match)\t\(wid)\t\(roundedInt(entry.frame.minX)),\(roundedInt(entry.frame.minY))\t\(roundedInt(entry.frame.width))x\(roundedInt(entry.frame.height))\t\(entry.title)")
            }
        }
        return
    }
    for entry in plan {
        guard let window = entry.window else { continue }
        moveWindow(window.element, x: entry.frame.minX, y: entry.frame.minY)
        resizeWindow(window.element, width: entry.frame.width, height: entry.frame.height)
    }
    let restored = plan.filter(\.willMove).count
    if restored == 0 && !plan.isEmpty {
        commandWarnings.append("no saved window was restored; run window-tool restore-layout \(shellQuoted(target)) --dry-run to see how each one matched")
    }
    commandResultFields = ["restored": restored, "total": plan.count]
    printStatus("Restored \(restored)/\(plan.count) window(s) for \(appOrder.count == 1 ? appOrder[0] : "\(appOrder.count) apps")")
}

/// Lists the named layouts in `layoutsDirectory` by name, ignoring case: window count, apps and when each was saved (the
/// file's modification time). A file that is not a layout is skipped with a warning.
func layoutsCommand() {
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: layoutsDirectory)) ?? [])
        .filter { $0.hasSuffix(".json") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    let entries = files.compactMap { file -> (name: String, path: String, windows: Int, apps: [String], saved: Date)? in
        let path = (layoutsDirectory as NSString).appendingPathComponent(file)
        guard let data = FileManager.default.contents(atPath: path), let layout = try? JSONDecoder().decode(WindowLayout.self, from: data) else {
            commandWarnings.append("\(path) is not a window-tool layout; skipped")
            return nil
        }
        var apps: [String] = []
        for window in layout.windows {
            if let id = window.bundleId ?? layout.bundleId, !apps.contains(id) { apps.append(id) }
        }
        let saved = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return (String(file.dropLast(".json".count)), path, layout.windows.count, apps, saved)
    }
    if config.jsonOutput {
        let formatter = ISO8601DateFormatter()
        printJSON(entries.map { ["name": $0.name, "path": $0.path, "windows": $0.windows, "apps": $0.apps, "saved": formatter.string(from: $0.saved)] as [String: Any] })
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("NAME\tWINDOWS\tAPPS\tSAVED")
        for entry in entries {
            print("\(entry.name)\t\(entry.windows)\t\(entry.apps.joined(separator: ","))\t\(formatter.string(from: entry.saved))")
        }
        if entries.isEmpty {
            fputs("No saved layouts. Save one with 'window-tool save-layout <name>'.\n", stderr)
        }
    }
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
    if !ndjson && !(once && config.jsonOutput) {
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

/// The text of an undo history entry's command line, such as `snap 0 left`.
func undoEntryLine(_ entry: UndoEntry) -> String {
    ([entry.command] + entry.arguments).joined(separator: " ")
}

/// Reverts the newest `steps` entries of the undo history, newest first, or with `command` only the newest entry that
/// command made (`tile --untile`, `sidebar --unpush`), and removes them from the history. A window that no longer
/// exists is skipped with a warning.
func undoCommand(steps: Int = 1, command: String? = nil) throws {
    config.skipUndoRecording = true
    var history = loadUndoHistory()
    let positions: [Int]
    if let command {
        guard let last = history.lastIndex(where: { $0.command == command }) else { throw WindowToolError.nothingToUndo(command: command) }
        positions = [last]
    } else {
        guard !history.isEmpty else { throw WindowToolError.nothingToUndo(command: nil) }
        guard steps <= history.count else {
            throw WindowToolError.invalidValue(name: "--steps", expected: "at most \(history.count), the number of changes in the undo history", got: "\(steps)")
        }
        positions = Array(history.indices.suffix(steps).reversed())
    }
    for position in positions {
        let entry = history[position]
        var restored = 0
        for frame in entry.windows {
            guard let window = findWindowByID(frame.windowID) else {
                commandWarnings.append("'\(frame.title)' (id=\(frame.windowID)) no longer exists; not restored")
                continue
            }
            moveWindow(window.element, x: CGFloat(frame.x), y: CGFloat(frame.y))
            resizeWindow(window.element, width: CGFloat(frame.width), height: CGFloat(frame.height))
            restored += 1
        }
        printStatus("Undid '\(undoEntryLine(entry))': restored \(restored) window(s)")
    }
    for position in positions.sorted(by: >) { history.remove(at: position) }
    try saveUndoHistory(history)
}

/// Prints the undo history, newest first; step N is what `undo --steps=N` reverts down to.
func undoListCommand() {
    let entries = Array(loadUndoHistory().reversed())
    if config.jsonOutput {
        let formatter = ISO8601DateFormatter()
        printJSON(["entries": entries.enumerated().map { step, entry in
            ["step": step + 1, "command": entry.command, "arguments": entry.arguments, "time": formatter.string(from: entry.time),
             "windows": entry.windows.map { ["bundle_id": $0.bundleId ?? NSNull(), "window_id": Int($0.windowID), "title": $0.title,
                                             "x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] as [String: Any] }] as [String: Any]
        }])
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("STEP\tTIME\tWINDOWS\tCOMMAND")
        for (step, entry) in entries.enumerated() {
            print("\(step + 1)\t\(formatter.string(from: entry.time))\t\(entry.windows.count)\t\(undoEntryLine(entry))")
        }
    }
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
    case elements = "Elements"
    case moveSize = "Move/size"
    case layout = "Layout"
    case overlays = "Overlays"
    case capture = "Capture"
    case meta = "Meta"
}

/// How a command uses --app. `optional` commands work without it: those taking a <window> find the app from an `id=`
/// selector, and `list` and `save-layout` cover every app.
enum AppUsage {
    case required, optional, none
}

/// One command's help. `synopsis` lists positional arguments only; " [options]" is added when `flags` is non-empty.
/// `mutates` is true when the command changes a window's position, size, state or focus; under `--json` such a
/// command prints the windows it recorded with `recordAffectedWindow` (see `reportAffectedWindows`).
/// `confirmationVerb` starts each of its `--verbose` lines (see `printConfirmations`). Every mutating command sets one,
/// or leaves it nil with a comment saying why it prints no lines.
/// `needsAccessibility` and `resolvesOwnApp` drive `runCommand`'s up-front checks; `commands --json` reports them.
struct CommandSpec {
    let name: String
    let group: CommandGroup
    let app: AppUsage
    let mutates: Bool
    var confirmationVerb: String? = nil
    var synopsis = ""
    let summary: String
    /// A shorter summary for the top-level help's command list, when `summary` is too long for one line there.
    var brief: String? = nil
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

/// The widest command synopsis the top-level help keeps on one line with its summary. It fits every synopsis except
/// snap's and watch's, which wrap, so the summary column does not move to the right of their long synopses.
let helpNameColumnLimit = 42

/// Formats name/description pairs as an indented two-column list. A name longer than `width` gets its description on
/// the next line, in the description column.
func helpRows(_ rows: [(name: String, description: String)], width: Int? = nil) -> [String] {
    let width = width ?? rows.map(\.name.count).max() ?? 0
    return rows.map { row in
        row.name.count > width
            ? "  \(row.name)\n" + String(repeating: " ", count: width + 4) + row.description
            : "  " + row.name.padding(toLength: width + 2, withPad: " ", startingAt: 0) + row.description
    }
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
    CommandSpec(name: "tree", group: .query, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Print a window's accessibility element tree: role, title, value, frame and actions", brief: "Print a window's accessibility element tree",
                flags: [("--depth N", "Levels below the window to show, 0 to 100 (default: 10); web content can print thousands of lines, so lower it there"),
                        ("--max-value N", "Cut string values to N characters, 0 for no limit (default: 200); --json marks a cut value with value_truncated")]),
    CommandSpec(name: "text", group: .query, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Print the text inside a window: label and text field values, one per line, escaped (--raw for readable text, --json for exact strings)", brief: "Print the text inside a window, one value per line",
                flags: [("--path <path>", "Read only the element at this path from 'tree' and its descendants, such as 0.2.1 (\"\" is the whole window, the default)"),
                        ("--focused", "Print only the value of the element with keyboard focus; --json prints just that element's object (exit 4 when nothing in the window has keyboard focus)"),
                        ("--raw", "Print line breaks and tabs inside values as they are (other control characters stay escaped)"),
                        ("--max-value N", "Cut values to N characters, 0 for no limit (default: 0); a cut value ends in … and --json marks it with value_truncated")]),
    CommandSpec(name: "count", group: .query, app: .required, mutates: false,
                summary: "Print the number of windows for --app"),
    CommandSpec(name: "active-window", group: .query, app: .none, mutates: false,
                summary: "Print info about the frontmost app's primary window",
                flags: [("--id", "Print only the window ID")]),
    CommandSpec(name: "active-screen", group: .query, app: .none, mutates: false,
                summary: "Print the active screen's usable bounds (--json: its full screens entry)", brief: "Print the active screen's usable bounds", needsAccessibility: false),
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

    // No confirmationVerb: press already prints "Performed <action> on <element>", and a second line per action is noise.
    CommandSpec(name: "press", group: .elements, app: .optional, mutates: true, synopsis: "<window>",
                summary: "Press a button or perform another accessibility action on one element of a window, found by one or more of --path, --role and --title", brief: "Press a button or perform another action on one element of a window",
                flags: [("--path <path>", "The element at this path from 'tree', such as 0.2.1; with --role/--title, the subtree to search (default: whole window)"),
                        ("--role <role>", "Only an element with exactly this role, such as AXButton"),
                        ("--title <title>", "Only an element with this whole title, ignoring case (unlike title=, not a substring); fails and lists the paths when several match"),
                        ("--action <action>", "The action to perform, as 'tree' lists it, such as AXShowMenu (default: AXPress)")]),
    CommandSpec(name: "snap", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Snapped", synopsis: "<window> <position> | <window> --rect=<x,y,w,h> | <window> --grid=<cols>x<rows> --cell=<col>,<row> [--span=<cols>,<rows>]",
                summary: "Snap a window to a screen region",
                arguments: [("<position>", SnapPosition.allNames)],
                flags: [("--rect <x,y,w,h>", "Snap to a region given as fractions of the visible frame (0 to 1, origin top left) instead of a position or --grid, e.g. --rect=0,0,0.7,1"),
                        ("--grid <cols>x<rows>", "Divide the visible frame into a grid and snap to --cell (required) instead of a position or --rect, e.g. --grid=6x4"),
                        ("--cell <col>,<row>", "With --grid, the region's top-left cell, counting from 0 at the top left, e.g. --cell=1,0"),
                        ("--span <cols>,<rows>", "With --grid, the region's size in cells (default: 1,1); it must fit inside the grid from --cell, e.g. --span=2,3")]),
    CommandSpec(name: "move", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Moved", synopsis: "<window> <x> <y> [<width> <height>]",
                summary: "Move a window, optionally resizing it",
                arguments: [("<x> <y>", "Top-left corner in screen points"),
                            ("<width> <height>", "New size in points")]),
    CommandSpec(name: "resize", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Resized", synopsis: "<window> <width> <height>",
                summary: "Resize a window"),
    CommandSpec(name: "center", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Centered", synopsis: "<window>",
                summary: "Center a window on its screen",
                flags: [("--size N", "Resize to N x N points first"),
                        ("--size W,H", "Resize to W x H points first (also --size WxH)")]),
    CommandSpec(name: "maximize", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Maximized", synopsis: "<window>",
                summary: "Maximize a window to fill its screen"),
    CommandSpec(name: "move-to-screen", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Moved", synopsis: "<window> <screen>",
                summary: "Move a window to another display",
                arguments: [("<screen>", "Display index from 'screens', or primary, external, left, right, next, prev (left, right, next and prev count from the window's display)")]),
    CommandSpec(name: "focus", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Focused", synopsis: "<window>",
                summary: "Bring a window to the front"),
    CommandSpec(name: "minimize", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Minimized", synopsis: "<window>",
                summary: "Minimize a window"),
    // No confirmationVerb: close prints its own "Closed N window(s)" line, and closed windows are not recorded.
    CommandSpec(name: "close", group: .moveSize, app: .optional, mutates: true, synopsis: "<window> | --all",
                summary: "Close a window, or every window of --app with --all",
                flags: [("--all", "Close every window of --app instead of one window")]),
    // `mutates` means "prints a window list under --json"; quit prints its own result instead, so it stays false although it is destructive.
    CommandSpec(name: "quit", group: .moveSize, app: .required, mutates: false,
                summary: "Quit --app and wait until it has exited",
                flags: [("--force", "Force-terminate the app; unsaved changes are lost")], needsAccessibility: false),
    CommandSpec(name: "restore", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Restored", synopsis: "[<window>]",
                summary: "Restore minimized windows: all for --app, or just <window>"),
    CommandSpec(name: "fullscreen", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Fullscreened", synopsis: "<window>",
                summary: "Enter macOS fullscreen"),
    CommandSpec(name: "unfullscreen", group: .moveSize, app: .optional, mutates: true, confirmationVerb: "Unfullscreened", synopsis: "<window>",
                summary: "Exit macOS fullscreen"),

    CommandSpec(name: "tile", group: .layout, app: .required, mutates: true, confirmationVerb: "Tiled", synopsis: "[<window>...]",
                summary: "Tile windows in a grid (all windows for --app when none are given)",
                flags: [("--gap N", "Gap between windows in pixels (default: 10)"),
                        ("--cols N", "Force a number of columns, greater than 0"),
                        ("--untile", "Undo the last tile: restore the windows it moved (no --app needed)")]),
    CommandSpec(name: "columnize", group: .layout, app: .optional, mutates: true, confirmationVerb: "Columnized", synopsis: "<window> <window> [<window>...]",
                summary: "Arrange windows side by side in columns",
                flags: [("--gap N", "Gap between columns in pixels (default: 10)")]),
    CommandSpec(name: "stack", group: .layout, app: .required, mutates: true, confirmationVerb: "Stacked", synopsis: "[<window>...] [--offset N]",
                summary: "Cascade the windows for --app, or just the ones named",
                arguments: [("[<window>...]", "Window selectors to cascade (default: all windows)"),
                            ("[offset]", "Legacy form of --offset: a lone bare number with no --offset")],
                flags: [("--offset N", "Pixels between each window (default: 30)")]),
    CommandSpec(name: "sidebar", group: .layout, app: .optional, mutates: true, confirmationVerb: "Moved", synopsis: "<window>",
                summary: "Pin a window to an edge of its screen",
                flags: [("--side left|right|top|bottom", "Edge to pin to (default: left)"),
                        ("--full-height", "Fill the screen height"),
                        ("--full-width", "Fill the screen width"),
                        ("--push", "Push overlapping windows away from the sidebar"),
                        ("--unpush", "Undo the last sidebar: restore the sidebar window and any windows it pushed (takes no <window>)")]),
    CommandSpec(name: "save-layout", group: .layout, app: .optional, mutates: false, synopsis: "<name-or-file>",
                summary: "Save the windows of every app, or only of --app, as a named layout or to a JSON file", brief: "Save the windows of every app, or of --app, as a named layout",
                arguments: [("<name-or-file>", "A layout name, saved in ~/.config/window-tool/layouts/, or a file path (containing '/' or ending in .json). Replaces an existing layout of the same name.")]),
    CommandSpec(name: "restore-layout", group: .layout, app: .none, mutates: true, confirmationVerb: "Restored", synopsis: "<name-or-file>",
                summary: "Move windows back to a saved layout (the layout names the apps)",
                arguments: [("<name-or-file>", "A layout name from 'layouts', or a file path (containing '/' or ending in .json)")],
                flags: [("--launch", "Open the layout's apps that are not running, and wait up to 10s for their windows"),
                        ("--dry-run", "Print where each window would go and how it was matched, without moving anything")]),
    CommandSpec(name: "layouts", group: .layout, app: .none, mutates: false,
                summary: "List the named layouts saved in ~/.config/window-tool/layouts/", needsAccessibility: false),
    CommandSpec(name: "undo", group: .layout, app: .none, mutates: true, confirmationVerb: "Undid", synopsis: "[--steps N | --list]",
                summary: "Revert the last command that moved or resized windows",
                flags: [("--steps N", "Revert the last N changes, newest first, greater than 0 (default: 1)"),
                        ("--list", "Show the undo history, newest first, without changing anything")]),

    CommandSpec(name: "highlight", group: .overlays, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Briefly highlight a window (blocks until it dismisses)",
                flags: [("--color <color>", "Overlay color (default: red)"),
                        ("--duration <seconds>", "How long to show it, 0 to 86400; 0 dismisses it at once (default: 3)")]),
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
                summary: "Dim everything except a window, tracking it until it closes",
                flags: [("--opacity <value>", "Overlay opacity, 0.0-1.0 (default: 0.5)"),
                        ("--duration <seconds>", "Dismiss after this long, up to 86400; 0 stays until 'undim' or the window closes (default: 0)")]),
    CommandSpec(name: "undim", group: .overlays, app: .none, mutates: false,
                summary: "Remove the active dim overlay", needsAccessibility: false),
    CommandSpec(name: "identify", group: .overlays, app: .optional, mutates: false,
                summary: "Label visible windows with their IDs (blocks until they dismiss)",
                flags: [("--color <color>", "Label color (default: magenta)"),
                        ("--duration <seconds>", "How long to show the labels, 0 to 86400; 0 dismisses them at once (default: 3)")], resolvesOwnApp: true),
    CommandSpec(name: "shake", group: .overlays, app: .optional, mutates: true, confirmationVerb: "Shook", synopsis: "<window> [--offset N] [--count N] [--delay <seconds>]",
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
                        ("--fps N", "Frames per second, 1 to 120 (default: 30)"),
                        ("--duration <seconds>", "Stop after this long, greater than 0 (default: until Ctrl-C)"),
                        ("--no-countdown", "Skip the 3-second countdown"),
                        ("--no-border", "Don't show a border while recording")]),
    CommandSpec(name: "pip", group: .capture, app: .optional, mutates: false, synopsis: "<window>",
                summary: "Show a live, always-on-top thumbnail of a window (blocks until Ctrl-C)",
                flags: [("--scale <factor>", "Size relative to the window, greater than 0 and at most 1 (default: 0.3)"),
                        ("--position <corner>", "top-left, top-right, bottom-left or bottom-right of the focused screen (default: bottom-right)"),
                        ("--fps N", "Most frames per second to show, 1 to 120 (default: 10)"),
                        ("--duration <seconds>", "Close the thumbnail after this long, greater than 0 (default: until Ctrl-C)")]),

    CommandSpec(name: "help", group: .meta, app: .none, mutates: false, synopsis: "[<command>]",
                summary: "Show all commands, or one command's arguments and options", needsAccessibility: false),
    CommandSpec(name: "commands", group: .meta, app: .none, mutates: false,
                summary: "List every command; with --json, its arguments, options, --app usage and whether it mutates", brief: "List every command (--json: arguments, options and more)",
                needsAccessibility: false),
    CommandSpec(name: "doctor", group: .meta, app: .none, mutates: false,
                summary: "Report the version and whether Accessibility and Screen Recording are granted", brief: "Report the version and whether permissions are granted",
                needsAccessibility: false),
    CommandSpec(name: "shell-init", group: .meta, app: .none, mutates: false, synopsis: "<shell>",
                summary: "Print a shell integration snippet",
                arguments: [("<shell>", "zsh, bash or fish")], needsAccessibility: false),
]

/// Prints the command list: names and summaries, or with --json the full table plus the valid values for enum-like arguments.
func commandsCommand() {
    if config.jsonOutput {
        printJSON(["version": VERSION, "commands": commandSpecs.map(\.json),
                   "global_flags": globalFlags.map { ["name": $0.name, "description": $0.description] },
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
        printJSON(["version": VERSION, "accessibility": accessibility, "screen_recording": screenRecording] as [String: Any])
    } else {
        func row(_ name: String, _ granted: Bool, _ needed: String) -> String {
            "\(name.padding(toLength: 17, withPad: " ", startingAt: 0))\(granted ? "granted" : "missing")  (\(needed))"
        }
        print("window-tool \(VERSION)")
        print(row("Accessibility", accessibility, "needed by every command that reads or changes windows"))
        print(row("Screen Recording", screenRecording, "needed by preview, record and pip"))
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

/// The options that go before or after any command; the top-level help and `commands --json` list them.
let globalFlags: [(name: String, description: String)] = [
    ("--app <name-or-id>", "Target application by name or bundle ID (an exact name wins over substrings); in a chain, it applies to its command and later ones"),
    ("--exact", "Match --app only as a whole app name or bundle ID, ignoring case; applies to every --app in the chain"),
    ("--json", "Output in JSON format"),
    ("--keep-going", "In a chain, run the remaining commands after one fails"),
    ("--first", "With title=, use the first match when several windows match (move, resize and maximize ignore it)"),
    ("--verbose", "After a command that changes windows, print one line per window (ignored with --json)"),
    ("--help, -h", "Show help; after a command, show that command's help"),
    ("--version, -v", "Print version and exit"),
]

/// Prints the top-level help: every command grouped as in `commandSpecs`, then selectors, options and chaining.
func usage() {
    let entries = commandSpecs.map { spec in
        (group: spec.group, name: [spec.name, spec.synopsis].filter { !$0.isEmpty }.joined(separator: " "), description: spec.brief ?? spec.summary)
    }
    let width = entries.map(\.name.count).filter { $0 <= helpNameColumnLimit }.max() ?? 0
    var lines = [
        "Usage: window-tool [--app <name-or-id>] [--exact] [--json] [--keep-going] [--first] [--verbose] <command> [args...]",
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
    \(helpRows(globalFlags).joined(separator: "\n"))
      Options that take a value accept --flag value or --flag=value.
      Unknown options and extra arguments are errors; the command does not run.

    Output:
      Results go to stdout and errors to stderr. With --json, a command that changes
      windows prints {"windows": [...], "warnings": [...]} instead of a status message:
      each changed window in the info schema, plus "requested" if it was moved or resized.
      Most of those commands print nothing on success; --verbose adds one line per
      changed window to stdout: Moved "Notes" "Todo" (id=1341) to 100,50 800x600
      (close and press print their own line instead).

    Errors and exit codes:
      With --json, an error also prints {"error": {"code", "message", "details"}}
      to stdout (in a chain, the failed command's "error"). Exit codes: 0 success,
      1 other failure, 2 usage error, 3 app not found or ambiguous, 4 window not
      found, 5 permission not granted (Accessibility, or Screen Recording for record),
      6 close blocked by an unsaved-changes prompt, 7 wait or watch --once timed out.

    Warnings:
      After a move or resize, the window's frame is re-read. If a set call failed or
      the frame differs from the request by more than 2 points (a minimum size, a
      fullscreen window), stderr gets "Warning: '<title>': size requested WxH but is WxH" and the exit
      code stays 0. With --json the message is also in the result's "warnings".

    Undo:
      Commands that move or resize windows save the frames they replace (the last 20
      changes, per user, cleared on restart). 'undo' reverts the newest, 'undo --list'
      shows them. focus, minimize, restore, fullscreen and close are not recorded.

    Command chaining:
      Use + to run multiple commands in sequence, sharing --json, --first, --exact and --verbose.
      Subsequent commands inherit the window selector from the previous command.
      --app may be given in any command of a chain: it applies to that command and the
      ones after it. A command that names a different app does not inherit the previous
      window selector:
      window-tool --app Safari focus 0 + --app Notes snap 0 left
      Bare numbers that fit a command's arguments are arguments (+ shake 20);
      use id= or title= to name another window:
      window-tool --app Safari snap 0 center + focus + highlight --color red
      window-tool --app iTerm info 0 + info 1
      window-tool focus id=2457 + highlight + dim id=2789

      A chain stops at the first failure unless --keep-going is given; the exit code
      is the first failure's. With --json, a chain prints one object:
      {"results": [{"command", "ok", "app", "data" or "error"}...], "failed_at": N or null}
      where N is the 1-based number of the first failed command, and app is the bundle ID
      of the --app in effect (null when none, or when the command ignores --app).

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

// Parse the global flags --json, --first, --keep-going, --exact and --verbose. Each may appear once; a repeat is a usage error like a repeated command option.
// --json is read first so the error is reported as JSON when the repeat is of --json itself.
func takeGlobalFlag(_ name: String) -> Bool {
    let given = takeFlag(name, from: &args)
    if given, args.contains(name) {
        if name == "--json" { config.jsonOutput = true }
        exitWithError(WindowToolError.repeatedOption(name, command: nil))
    }
    return given
}
if takeGlobalFlag("--json") { config.jsonOutput = true }
if takeGlobalFlag("--first") { config.firstMatch = true }
if takeGlobalFlag("--keep-going") { config.keepGoing = true }
if takeGlobalFlag("--exact") { config.exactApp = true }
if takeGlobalFlag("--verbose") { config.verbose = true }

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

/// One command of a chain: its args without --app, and the --app it names, if any.
typealias ChainCommand = (args: [String], app: String?)

/// Returns each command of the chain with the --app it names, taken from before or after its command name. An --app
/// applies to its command and every later one until another command names one. A leading part that is only --app
/// (`--app Safari + list`) belongs to the first command. Fails before anything runs on a missing, empty or repeated
/// --app, or one with no command after it in its part of the chain.
func takeChainApps(_ parts: [[String]]) throws -> [ChainCommand] {
    // A missing value (takeOption throws) and an empty one get the same error.
    let missingApp = WindowToolError.invalidValue(name: "--app", expected: "an app name or bundle ID (e.g. --app Finder)", got: "")
    var commands: [ChainCommand] = []
    var leading: String?
    for var part in parts {
        var apps: [String] = []
        do { while let app = try takeOption("--app", from: &part) { apps.append(app) } } catch { throw missingApp }
        if apps.contains("") { throw missingApp }
        if apps.count > 1 || (!apps.isEmpty && leading != nil) {
            throw WindowToolError.repeatedOption("--app", command: part.first)
        }
        if part.isEmpty, let app = apps.first {
            guard commands.isEmpty else {
                throw WindowToolError.invalidValue(name: "--app", expected: "followed by a command in its part of the chain, as in '+ --app Notes list'", got: app)
            }
            leading = app
        } else {
            commands.append((part, apps.first ?? leading))
            leading = nil
        }
    }
    return commands
}

let chainCommands: [ChainCommand]
do {
    chainCommands = try takeChainApps(splitCommands(args))
} catch {
    exitWithError(error)
}

guard let firstArgs = chainCommands.first?.args else {
    usage()
    exit(0)
}

if firstArgs.first == "--version" || firstArgs.first == "-v" {
    if config.jsonOutput {
        printJSON(["version": VERSION])
    } else {
        print("window-tool \(VERSION)")
    }
    exit(0)
}

// `<command> --help` (or -h) anywhere in a chain shows that command's help and runs nothing.
let helpTarget = chainCommands.first { $0.args.dropFirst().contains { $0 == "--help" || $0 == "-h" } }
let commandGroups: [ChainCommand] = helpTarget.map { [(["help", $0.args[0]], nil)] } ?? chainCommands

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
        let resolvedBundleId: String? = config.bundleId.isEmpty ? nil : try resolveAppIdentifier(config.bundleId)
        try listCommand(bundleId: resolvedBundleId, titleGlob: titleGlob, screen: screen, visibleOnly: visibleOnly,
                        excludeMinimized: excludeMinimized, sort: sort, idsOnly: idsOnly, fields: fields, includeAll: includeAll)
    case "info":
        try infoCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector)
    case "tree":
        let depth = try takeOption("--depth", from: &rest).map { try parseNonNegativeInt($0, label: "--depth", max: maxTreeDepth) } ?? 10
        let maxValue = try takeOption("--max-value", from: &rest).map { try parseNonNegativeInt($0, label: "--max-value") } ?? 200
        try treeCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector, depth: depth, maxValue: maxValue)
    case "text":
        let path = try takeOption("--path", from: &rest) ?? ""
        let focusedOnly = takeFlag("--focused", from: &rest)
        let raw = takeFlag("--raw", from: &rest)
        let maxValue = try takeOption("--max-value", from: &rest).map { try parseNonNegativeInt($0, label: "--max-value") } ?? 0
        try textCommand(bundleId: config.bundleId, selector: try resolveSelectorAndArgs(rest, command: command).selector, path: path,
                        focusedOnly: focusedOnly, raw: raw, maxValue: maxValue)
    case "press":
        let path = try takeOption("--path", from: &rest)
        let role = try takeOption("--role", from: &rest)
        let title = try takeOption("--title", from: &rest)
        let action = try takeOption("--action", from: &rest) ?? kAXPressAction
        if action.isEmpty { throw WindowToolError.invalidValue(name: "--action", expected: "an action name from 'tree', such as AXPress", got: action) }
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        if path == nil, role == nil, title == nil {
            throw WindowToolError.optionRequired(option: "--path", command: command, placeholder: "<path>, --role <role> or --title <title>")
        }
        try pressCommand(bundleId: config.bundleId, selector: selector, path: path ?? "", role: role, title: title, action: action)
    case "columnize":
        let gap = try takeOption("--gap", from: &rest).map { try parseInt($0, label: "--gap") } ?? 10
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
            try undoCommand(command: "tile")
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
        let fractionRect = try parseRectFlag(&rest)
        let gridRect = try parseGridFlags(&rest)
        if fractionRect != nil, gridRect != nil {
            throw WindowToolError.unexpectedArgument("--rect", command: command, conflictsWith: "--grid")
        }
        let region = fractionRect ?? gridRect
        let (selector, values) = try resolveSelectorAndArgs(rest, command: command, argCounts: [region == nil ? 1 : 0])
        if let region {
            try checkArgs(values, command: command)
            try snapCommand(bundleId: config.bundleId, selector: selector, position: nil, rect: region)
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
            try undoCommand(command: "sidebar")
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
        guard let target = try checkArgs(rest, command: command, max: 1).first else {
            throw WindowToolError.missingArguments(command: "save-layout")
        }
        // An empty config.bundleId means no --app was given: save every app.
        try saveLayoutCommand(bundleId: config.bundleId.isEmpty ? nil : config.bundleId, target: target)
    case "restore-layout":
        let launch = takeFlag("--launch", from: &rest)
        let dryRun = takeFlag("--dry-run", from: &rest)
        guard let target = try checkArgs(rest, command: command, max: 1).first else {
            throw WindowToolError.missingArguments(command: "restore-layout")
        }
        try restoreLayoutCommand(target: target, launch: launch, dryRun: dryRun)
        // A dry run moves nothing; its plan is its result, so no windows result follows it.
        config.printedOwnResult = dryRun
    case "layouts":
        try checkArgs(rest, command: command)
        layoutsCommand()
    case "undo":
        // undo is a mutating command, but --list changes nothing and prints the history as its result,
        // so it sets printedOwnResult to stop the main loop from printing an empty windows result after it.
        let steps = try takeOption("--steps", from: &rest)
        let list = takeFlag("--list", from: &rest)
        try checkArgs(rest, command: command)
        if list {
            if let steps { throw WindowToolError.invalidValue(name: "--steps", expected: "left out when --list is given", got: steps) }
            undoListCommand()
            config.printedOwnResult = true
        } else {
            try undoCommand(steps: try steps.map { try parsePositiveInt($0, label: "--steps") } ?? 1)
        }
    case "stack":
        var offset = try takeOption("--offset", from: &rest).map { try parseInt($0, label: "--offset") }
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
        let timeout = try takeOption("--timeout", from: &rest).map { try parsePositiveDouble($0, label: "--timeout") } ?? 30
        let stable = try stableArg.map { try parsePositiveDouble($0, label: "--stable") }
        if gone, let stableArg {
            throw WindowToolError.invalidValue(name: "--stable", expected: "left out when --gone is given (a window that is gone has no frame)", got: stableArg)
        }
        try waitCommand(selector: try resolveSelectorAndArgs(rest, command: command).selector, gone: gone, stable: stable, timeout: timeout)
    case "watch":
        let namedInterval = try takeOption("--interval", from: &rest)
        let ndjson = takeFlag("--ndjson", from: &rest)
        let once = takeFlag("--once", from: &rest)
        let watchTimeout = try takeOption("--timeout", from: &rest).map { try parsePositiveDouble($0, label: "--timeout") }
        let positionalInterval = try checkArgs(rest, command: command, max: namedInterval == nil ? 1 : 0).first
        let interval = try (namedInterval ?? positionalInterval).map { try parsePositiveDouble($0, label: namedInterval != nil ? "--interval" : "interval") } ?? 1.0
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
        let offset = try (namedOffset ?? legacyOffset).map { try parseInt($0, label: namedOffset != nil ? "--offset" : "offset") } ?? 12
        let count = try (namedCount ?? legacyCount).map { try parsePositiveInt($0, label: namedCount != nil ? "--count" : "count") } ?? 6
        let delay = try (namedDelay ?? legacyDelay).map { try parseDouble($0, label: namedDelay != nil ? "--delay" : "delay") } ?? 0.04
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
        let identifyDuration = try takeOption("--duration", from: &rest).map(parseOverlayDuration) ?? 3.0
        let identifyColor = try takeOption("--color", from: &rest).map(parseColor) ?? .magenta
        try checkArgs(rest, command: command)
        let resolvedBundleId: String? = config.bundleId.isEmpty ? nil : try resolveAppIdentifier(config.bundleId)
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
    case "pip":
        let pipFlags = try parsePipFlags(&rest)
        let selector = try resolveSelectorAndArgs(rest, command: command).selector
        try pipCommand(bundleId: config.bundleId, selector: selector, scale: pipFlags.scale, corner: pipFlags.corner, fps: pipFlags.fps, duration: pipFlags.duration)
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
for (index, (group, app)) in commandGroups.enumerated() {
    config.runningCommand = group[0]
    // A command that names a different app from the previous command's does not inherit its window, which belongs to that app.
    var droppedSelector = false
    if let app {
        let resolve = { (app: String) in app.isEmpty ? "" : (try? resolveAppIdentifier(app)) ?? app }
        if config.lastSelector != nil, resolve(app) != resolve(config.bundleId) {
            config.lastSelector = nil
            droppedSelector = true
        }
        config.bundleId = app
    }
    do {
        try runCommand(group)
        recordUndoEntry(group)
        // `tile --untile` and `sidebar --unpush` are undo aliases, so they confirm with undo's verb.
        let isUndoAlias = (group[0] == "tile" && group.contains("--untile")) || (group[0] == "sidebar" && group.contains("--unpush"))
        if config.verbose && !config.jsonOutput, let verb = commandSpec(named: isUndoAlias ? "undo" : group[0])?.confirmationVerb { printConfirmations(verb: verb) }
        reportAffectedWindows(asJSON: config.jsonOutput && commandSpec(named: group[0])?.mutates == true && !config.printedOwnResult)
        config.printedOwnResult = false
        recordChainResult()
    } catch {
        // Windows a failed command already moved can still be undone. reportAffectedWindows does not run here,
        // so a warning from saving the history is printed directly.
        recordUndoEntry(group)
        commandWarnings.forEach { fputs("Warning: \($0)\n", stderr) }
        affectedWindows = []
        commandWarnings = []
        commandResultFields = [:]
        var error = error
        switch error {
        case WindowToolError.optionNeedsValue(let option, nil):
            error = WindowToolError.optionNeedsValue(option, command: group[0])
        case WindowToolError.appRequired(let hint) where commandGroups.dropFirst(index + 1).contains(where: { $0.app != nil }):
            error = WindowToolError.appRequired(hint: (hint ?? WindowToolError.appRequiredHint)
                + " --app applies to its own command and later ones; put it on or before the first command that needs it.")
        case WindowToolError.missingWindowSelector(let command, nil) where droppedSelector:
            error = WindowToolError.missingWindowSelector(command: command,
                hint: "A command that names a different --app does not inherit the previous command's window.")
        default:
            break
        }
        let prefix = commandGroups.count > 1 ? "Error in command \(index + 1) (\(group[0]))" : "Error"
        guard config.keepGoing else { exitWithError(error, prefix: prefix) }
        let code = reportError(error, prefix: prefix).exitCode
        firstFailureCode = firstFailureCode ?? code
    }
}
flushJSONAndExit(firstFailureCode ?? 0)
