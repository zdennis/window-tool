# window-tool

A fast macOS CLI for listing, moving, and resizing application windows using the Accessibility API (`AXUIElement`). Designed as a faster alternative to AppleScript for window management automation.

## Requirements

- macOS
- Swift compiler (`swiftc`) — included with Xcode or Xcode Command Line Tools
- Accessibility permissions for the calling terminal app (System Settings > Privacy & Security > Accessibility)

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

#### list

List all windows with their index, position, size, and title.

```sh
window-tool list
```

Output (tab-separated):

```
0    100,50    1200x900    My Window Title
1    200,100   800x600     Another Window
```

#### count

Print the number of windows.

```sh
window-tool count
```

#### move

Move and optionally resize a window by index.

```sh
window-tool move <index> <x> <y> [<width> <height>]
```

Examples:

```sh
window-tool move 0 100 50              # move only
window-tool move 0 100 50 1200 900     # move and resize
```

#### move-by-title

Move and optionally resize all windows matching a title substring.

```sh
window-tool move-by-title <pattern> <x> <y> [<width> <height>]
```

Example:

```sh
window-tool move-by-title "my-notes" 0 0 1400 1000
```

#### screens

List all displays with their bounds.

```sh
window-tool screens
```

Output (tab-separated): index, frame origin, frame size, visible origin, visible size, and flags (`main`, `mouse`).

```
0    0,0    5120x2160    0,0    5120x2129 [main,mouse]
1    -3840,560    3840x1600    -3840,560    3840x1600
```

#### active-screen

Print the bounds of the screen where the mouse cursor is (tab-separated: x, y, width, height). Coordinates use top-left origin, suitable for window positioning.

```sh
window-tool active-screen
```

### Options

| Option | Description |
|--------|-------------|
| `--app <bundle-id>` | Target application bundle ID (default: `com.googlecode.iterm2`) |

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
