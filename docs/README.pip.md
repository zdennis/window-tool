# window-tool pip

Show a live, always-on-top thumbnail of a window, so you can watch it while working in another.

## Usage

```sh
window-tool [--app <name-or-id>] pip <window> [--scale <factor>] [--position <corner>] [--fps N] [--duration <seconds>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command, unless this command names a different `--app`. |

## Options

| Option | Description |
|--------|-------------|
| `--scale <factor>` | Thumbnail size relative to the window, greater than 0 and at most 1 (default: 0.3) |
| `--position <corner>` | `top-left`, `top-right`, `bottom-left` or `bottom-right`, the same corner names as `snap` (default: `bottom-right`) |
| `--fps N` | Most frames per second to show, 1 to 120 (default: 10) |
| `--duration <seconds>` | Close the thumbnail after this many seconds, greater than 0 (default: stay open until Ctrl-C) |

## Details

Opens a borderless thumbnail that floats above other windows and shows on every Space, placed 20 points in from the chosen corner of the screen that has keyboard focus. It is the window's size times `--scale`, shrunk further if needed to fit that screen. The window is captured with ScreenCaptureKit, which sends a frame only when its content changes, so an idle window costs little. The thumbnail keeps the size it opened with; if the window is resized, its picture is scaled to fit. Drag the thumbnail to move it.

pip blocks until you press Ctrl-C (or send SIGTERM), the watched window closes, or `--duration` passes. It then exits 0 and prints nothing on stdout, with or without `--json`. Once capture starts, it prints `Showing window <id> in a thumbnail ...` on stderr. A window minimized or moved off-screen after that keeps showing its last frame. A window that is already minimized when pip starts shows black until it is restored, and one that ScreenCaptureKit cannot find fails with `no_window_matching_id` (exit 4).

Requires Screen Recording permission; without it, pip exits 5 with `screen_recording_not_enabled` before opening the thumbnail.

### Scripts and chains

- In a chain, the next command runs only after the thumbnail closes, and under `--json` the chain's result object prints only then. Use `--duration` to bound it.
- For unattended scripts, prefer `--duration` so pip always ends on its own.
- Run in the background with `&`, there is no signal that the thumbnail is up, and a failure after launch shows only in the exit status from `wait $pid`.
- To close it from another process, send SIGTERM: `kill $pid`, or `pkill -f 'window-tool.* pip id=2457'`.

## Examples

```sh
window-tool pip id=2457
window-tool --app Terminal pip 0 --scale 0.25 --position top-right
window-tool --app Safari pip title="Build" --fps 2 --duration 600

# Watch for 30 seconds, then focus the window
window-tool pip id=2457 --duration 30 + focus

# Run it in the background and close it later
window-tool pip id=2457 & pip_pid=$!
kill $pip_pid
wait $pip_pid; echo "pip exited $?"
```
