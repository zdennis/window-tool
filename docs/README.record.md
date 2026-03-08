# window-tool record

Record video of a window to a file.

## Usage

```sh
window-tool [--app <name-or-id>] record <window> --output <path> [options]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |

## Options

| Option | Description |
|--------|-------------|
| `--output <path>` | Output file path (.mov or .mp4) -- required |
| `--fps <N>` | Frames per second (default: 30) |
| `--duration <seconds>` | Stop recording after this many seconds |
| `--no-countdown` | Skip the 3-second countdown |
| `--no-border` | Don't show a border overlay during recording |

## Details

Records the window contents using ScreenCaptureKit. By default, shows a 3-second countdown and a colored border overlay (red during countdown, green while recording). Press Ctrl-C to stop recording. Requires Screen Recording permission.

Prints the output file path on completion. With `--json`, outputs path, window_id, width, and height.

## Examples

```sh
window-tool record 0 --output ~/recording.mov
window-tool record 0 --output ~/clip.mp4 --duration 10 --fps 60
window-tool record title="Demo" --output demo.mov --no-countdown --no-border
```
