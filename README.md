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

The compiled binary is placed in `bin/window-tool`.

## Usage

```
window-tool [--app <bundle-id>] <command> [args...]
```

By default, window-tool targets iTerm2 (`com.googlecode.iterm2`). Use `--app` to target a different application.

### Commands

| Command | Docs | Description |
|---------|------|-------------|
| `active-screen` | [README](docs/README.active-screen.md) | Print active screen bounds |
| `columnize` | [README](docs/README.columnize.md) | Arrange windows side-by-side in columns |
| `count` | [README](docs/README.count.md) | Print number of windows |
| `focus` | [README](docs/README.focus.md) | Bring window to front by index |
| `focus-by-title` | [README](docs/README.focus.md) | Bring window to front by title match |
| `fullscreen` | [README](docs/README.fullscreen.md) | Enter macOS fullscreen mode |
| `fullscreen-by-title` | [README](docs/README.fullscreen.md) | Enter fullscreen by title match |
| `info` | [README](docs/README.info.md) | Show detailed info for a window |
| `list` | [README](docs/README.list.md) | List all windows with index, position, size, and title |
| `list-open-windows` | [README](docs/README.list-open-windows.md) | List apps with open windows |
| `maximize` | [README](docs/README.maximize.md) | Maximize window to fill screen |
| `maximize-by-title` | [README](docs/README.maximize.md) | Maximize windows matching title |
| `minimize` | [README](docs/README.minimize.md) | Minimize a window by index |
| `minimize-by-title` | [README](docs/README.minimize.md) | Minimize a window by title match |
| `move` | [README](docs/README.move.md) | Move/resize window by index |
| `move-by-title` | [README](docs/README.move.md) | Move/resize windows matching title |
| `move-to-screen` | [README](docs/README.move-to-screen.md) | Move window to a different display |
| `move-to-screen-by-title` | [README](docs/README.move-to-screen.md) | Move window to display by title |
| `resize` | [README](docs/README.resize.md) | Resize window by index |
| `resize-by-title` | [README](docs/README.resize.md) | Resize windows matching title |
| `restore` | [README](docs/README.restore.md) | Restore all minimized windows |
| `restore-layout` | [README](docs/README.restore-layout.md) | Restore window layout from a JSON file |
| `save-layout` | [README](docs/README.save-layout.md) | Save window layout to a JSON file |
| `screens` | [README](docs/README.screens.md) | List all displays with bounds |
| `shake` | [README](docs/README.shake.md) | Shake a window by index |
| `shake-by-title` | [README](docs/README.shake.md) | Shake a window by title match |
| `snap` | [README](docs/README.snap.md) | Snap window to screen region |
| `snap-by-title` | [README](docs/README.snap.md) | Snap window to screen region by title |
| `stack` | [README](docs/README.stack.md) | Cascade windows with offset |
| `unfullscreen` | [README](docs/README.unfullscreen.md) | Exit macOS fullscreen mode |
| `unfullscreen-by-title` | [README](docs/README.unfullscreen.md) | Exit fullscreen by title match |
| `watch` | [README](docs/README.watch.md) | Watch for window changes |

### Options

| Option | Description |
|--------|-------------|
| `--app <bundle-id>` | Target application bundle ID (default: `com.googlecode.iterm2`) |
| `--json` | Output in JSON format |
| `--version`, `-v` | Print version and exit |

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
