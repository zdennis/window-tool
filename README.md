# window-tool

A fast macOS CLI for listing, moving, and resizing application windows using the Accessibility API (`AXUIElement`). Designed as a faster alternative to AppleScript for window management automation.

## Requirements

- macOS
- Swift compiler (`swiftc`) — included with Xcode or Xcode Command Line Tools

### Accessibility permissions

window-tool uses the macOS Accessibility API, which requires explicit user consent. You must grant Accessibility access to the terminal app you run window-tool from (e.g., iTerm2, Terminal.app):

1. Open **System Settings > Privacy & Security > Accessibility**
2. Click the **+** button and add your terminal application
3. If it's already listed, toggle it off and on again

Without this, commands that interact with windows (`list`, `move`, `focus`, etc.) will fail with an error.

## Building

```sh
./build.sh
```

The compiled binary is placed in `bin/window-tool`. `bin/` is gitignored and not on your `PATH`; to run `window-tool` from anywhere, link it into a directory that is:

```sh
sudo ln -s "$PWD/bin/window-tool" /usr/local/bin/window-tool
```

If `/usr/local/bin` does not exist (common on Apple Silicon), use `ln -s "$PWD/bin/window-tool" /opt/homebrew/bin/window-tool` with Homebrew, or any directory already on your `PATH`. Rebuilding updates the linked binary in place.

## Usage

```
window-tool [--app <name-or-id>] <command> [args...]
window-tool help [<command>]
```

Run `window-tool help` for every command grouped by purpose, and `window-tool help <command>` or `window-tool <command> --help` for one command's arguments and options. `window-tool --json commands` prints the same table as JSON.

Use `--app` to target a specific application by name or bundle ID. `--app` is required whenever you select a window by index or `title=`; there is no frontmost-app default. With `id=<N>` selectors, `--app` is optional because the owning app is detected automatically.

Window indexes change as windows open, close or minimize, so prefer `id=` in scripts (find IDs with `list`, `identify` or `pick`) and use `title=` or an index for interactive use.

### Commands

| Command | Docs | Description |
|---------|------|-------------|
| `active-screen` | [README](docs/README.active-screen.md) | Print active screen usable bounds |
| `active-window` | [README](docs/README.active-window.md) | Print info about the frontmost window |
| `border` | [README](docs/README.border.md) | Add a persistent border that tracks a window |
| `center` | [README](docs/README.center.md) | Center a window on screen, optionally resizing |
| `columnize` | [README](docs/README.columnize.md) | Arrange windows side-by-side in columns |
| `commands` | [README](docs/README.commands.md) | List every command; with `--json`, its arguments, options and whether it mutates |
| `count` | [README](docs/README.count.md) | Print number of windows |
| `dim` | [README](docs/README.dim.md) | Dim everything except a window |
| `flash` | [README](docs/README.flash.md) | Flash a colored overlay on a window |
| `focus` | [README](docs/README.focus.md) | Bring a window to front |
| `fullscreen` | [README](docs/README.fullscreen.md) | Enter macOS fullscreen mode |
| `help` | [README](docs/README.help.md) | Show all commands, or one command's arguments and options |
| `highlight` | [README](docs/README.highlight.md) | Briefly highlight a window with a border (blocks until it dismisses) |
| `identify` | [README](docs/README.identify.md) | Show window IDs on all windows (blocks while shown) |
| `info` | [README](docs/README.info.md) | Show detailed info for a window |
| `list` | [README](docs/README.list.md) | List windows (all apps, or one app with --app) |
| `maximize` | [README](docs/README.maximize.md) | Maximize a window to fill screen |
| `minimize` | [README](docs/README.minimize.md) | Minimize a window |
| `move` | [README](docs/README.move.md) | Move/resize a window |
| `move-to-screen` | [README](docs/README.move-to-screen.md) | Move a window to a different display |
| `pick` | [README](docs/README.pick.md) | Click a window to print its ID |
| `preview` | [README](docs/README.preview.md) | Capture a window screenshot as PNG |
| `record` | [README](docs/README.record.md) | Record video of a window |
| `resize` | [README](docs/README.resize.md) | Resize a window |
| `restore` | [README](docs/README.restore.md) | Restore all minimized windows |
| `restore-layout` | [README](docs/README.restore-layout.md) | Restore window layout from a JSON file |
| `save-layout` | [README](docs/README.save-layout.md) | Save window layout to a JSON file |
| `screens` | [README](docs/README.screens.md) | List all displays with bounds |
| `shake` | [README](docs/README.shake.md) | Shake a window to draw attention |
| `shell-init` | [README](docs/README.shell-init.md) | Print shell integration snippet |
| `sidebar` | [README](docs/README.sidebar.md) | Pin a window to screen edge as a sidebar |
| `snap` | [README](docs/README.snap.md) | Snap a window to a screen region |
| `stack` | [README](docs/README.stack.md) | Cascade all or selected windows with an offset |
| `tile` | [README](docs/README.tile.md) | Tile windows in a grid layout |
| `unborder` | [README](docs/README.unborder.md) | Remove border overlays for an app |
| `unborder-all` | [README](docs/README.unborder-all.md) | Remove all active borders |
| `undim` | [README](docs/README.undim.md) | Remove active dim overlay |
| `unfullscreen` | [README](docs/README.unfullscreen.md) | Exit macOS fullscreen mode |
| `watch` | [README](docs/README.watch.md) | Watch for window changes |

### Options

| Option | Description |
|--------|-------------|
| `--app <name-or-id>` | Target application by name or bundle ID; an exact app name (case-insensitive) wins over substring matches |
| `--json` | Output in JSON format. Commands that change windows print the changed windows instead of status messages such as `Moved 2 window(s)…` (see [Mutating command results](#mutating-command-results)) |
| `--keep-going` | In a chain, run the remaining commands after one fails; exit with the first failure's code (see [Command chaining](#command-chaining)) |
| `--help`, `-h` | Show help; after a command, show that command's help without running it |
| `--version`, `-v` | Print version and exit |

Options that take a value accept both `--flag value` and `--flag=value` (`--size 800` or `--size=800`, `--app Safari` or `--app=Safari`).

A command's options can come before or after its arguments. An option the command does not take, a repeated option, or an extra argument is an error, and the command fails before touching any window: `Unknown option '--foo' for 'center'. Run 'window-tool center --help'.` Negative numbers such as `-100` are arguments, not options.

### Command chaining

Use `+` to run multiple commands in sequence, sharing `--app` and `--json` flags. Subsequent commands inherit the window selector from the previous command when one is not provided, so you only need to specify the target window once. Once a command resolves a window, later commands in the chain target it by window ID, so they keep hitting the same window even after `focus` reorders the window list. In a chain, `move`, `resize`, `snap`, `move-to-screen` and `shake` read bare numbers that fit their own arguments as arguments, not as a window index (`+ shake 20`, `+ move 100 200 800 600`); use `id=` or `title=` to name a different window:

```sh
# Snap window 0 to center, then focus and highlight it (selector inherited)
window-tool --app Safari snap 0 center + focus + highlight --color red

# Each command can use its own selector
window-tool --app iTerm info 0 + info 1

# Mix explicit and inherited selectors
window-tool focus id=2457 + highlight + dim id=2789
```

A chain stops at the first failing command and exits with that command's error code. With `--keep-going`, the remaining commands still run, each failure is reported on stderr, and the exit code is the first failure's.

With `--json`, a chain always prints one object, whatever its length and wherever it failed. `results` has one entry per command that ran, in order: `command`, `ok`, and either `data` (what the command prints on its own with `--json`, or `null` for commands that print nothing) or `error` (the same `{code, message, details}` object a single command prints). `failed_at` is the 1-based number of the first failed command, matching `Error in command N` on stderr, or `null` when every command succeeded. Without `--keep-going`, commands after `failed_at` did not run. A single command keeps its bare shape.

Abbreviated output:

```sh
$ window-tool --json --app Finder count + info 99 + count
{
  "failed_at" : 2,
  "results" : [
    { "command" : "count", "data" : { "count" : 4 }, "ok" : true },
    { "command" : "info", "error" : { "code" : "window_index_out_of_range", ... }, "ok" : false }
  ]
}
```

This replaces the array that chains printed before (one bare result per command, then a bare error object), which changed shape with the chain's length and did not say which command failed.

### Errors and exit codes

Errors go to stderr as `Error: <message>`. With `--json`, the error is also printed to stdout (in a chain, as the failed command's `error`; see [Command chaining](#command-chaining)) as an object with a stable `code`, the `message`, and a `details` object holding the values behind the message:

```sh
$ window-tool --json --app Finder info 99
{
  "error" : {
    "code" : "window_index_out_of_range",
    "details" : {
      "count" : 4,
      "index" : 99
    },
    "message" : "Window index 99 out of range (0..3)"
  }
}
```

| Exit code | Meaning | Error codes |
|-----------|---------|-------------|
| 0 | Success | |
| 1 | Other failure | `operation_failed`, `nothing_to_undo`, `file_not_found` |
| 2 | Usage error: fix the command line | `unknown_command`, `unknown_option`, `repeated_option`, `unexpected_argument`, `option_needs_value`, `option_takes_no_value`, `option_required`, `missing_arguments`, `missing_window_selector`, `invalid_value`, `unknown_choice`, `app_required`, `screen_index_out_of_range` |
| 3 | `--app` matched no running app, or more than one | `app_not_found`, `ambiguous_app` |
| 4 | Window not found | `window_index_out_of_range`, `no_window_matching_title`, `no_window_matching_id`, `no_windows`, `no_pickable_window` |
| 5 | Permission not granted | `accessibility_not_enabled`, `screen_recording_not_enabled` |

### Mutating command results

With `--json`, every command that changes windows (`move`, `resize`, `snap`, `center`, `maximize`, `move-to-screen`, `focus`, `minimize`, `restore`, `fullscreen`, `unfullscreen`, `tile`, `columnize`, `stack`, `sidebar`, `restore-layout`, `shake`) prints the windows it changed, re-read after the change, in the `info` schema with the owning app's `bundle_id`. A window that was moved or resized also has `requested`, the frame it was asked for, so you can compare it with the frame it got. `index` is left out for a window that is not in its app's window list. `windows` is empty when nothing changed (`restore` with no minimized windows, `restore-layout` with no matching titles). The result is read right after the change, so `fullscreen` and `minimized` can still show the old state while macOS animates the transition; run `info` again to confirm. In a chain this object is the command's `data`. `save-layout` changes no windows; with `--json` it prints the layout it saved, plus `path`.

After a move or resize, window-tool re-reads the frame. When a set call failed, or the frame differs from the request by more than 2 points (a window with a minimum size, a fullscreen window), stderr gets `Warning: '<title>': size requested 400x300 but is 600x400`, the same message goes in `warnings`, and the exit code stays 0.

Abbreviated output:

```sh
$ window-tool --json --app Safari resize 0 400 300
{
  "warnings" : [ "'Start Page': size requested 400x300 but is 600x400" ],
  "windows" : [
    {
      "bundle_id" : "com.apple.Safari", "index" : 0, "window_id" : 1341, "title" : "Start Page",
      "x" : 100, "y" : 50, "width" : 600, "height" : 400,
      "requested" : { "width" : 400, "height" : 300 },
      "focused" : true, "main" : true, "minimized" : false, "fullscreen" : false, "modal" : false, ...
    }
  ]
}
```

## How it works

window-tool uses the macOS Accessibility API (`AXUIElement`) for window operations, which is significantly faster than AppleScript's inter-process communication. Window operations are near-instant.

For screen information, it uses `NSScreen` APIs and converts coordinates from macOS bottom-left origin to the top-left origin used by the Accessibility API for window positioning.

## Releasing

Releases are tagged on the `main` branch using `release.sh`, which follows [semver](https://semver.org/) with a `vM.m.p` format.

```sh
./release.sh              # print current version
./release.sh patch        # bump patch: v0.1.0 -> v0.1.1
./release.sh minor        # bump minor: v0.1.0 -> v0.2.0
./release.sh major        # bump major: v0.1.0 -> v1.0.0
./release.sh 2.0.0        # set explicit version (prompts for confirmation)
```

The script will:
1. Verify you are on the `main` branch with a clean working tree
2. Compute the new version (or prompt for confirmation if explicit)
3. Create a git tag and push it to origin

## License

MIT
