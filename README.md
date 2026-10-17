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

Run `window-tool help` for every command grouped by purpose, and `window-tool help <command>` or `window-tool <command> --help` for one command's arguments and options.

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
| `stack` | [README](docs/README.stack.md) | Cascade windows with offset |
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
| `--json` | Output in JSON format. Status messages (such as `Moved 2 window(s)…`) go to stderr so stdout stays valid JSON |
| `--help`, `-h` | Show help; after a command, show that command's help without running it |
| `--version`, `-v` | Print version and exit |

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

A chain stops at the first failing command and exits 1. With `--json`, results from the commands that ran before the failure are still printed to stdout, and the error goes to stderr.

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
