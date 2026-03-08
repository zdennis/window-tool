# window-tool preview

Capture a window screenshot as a PNG image.

## Usage

```sh
window-tool [--app <name-or-id>] preview <window> [--output <path>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--output <path>` | Output file path (default: `/tmp/window-tool-preview-<wid>.png`) |

## Details

Captures the window contents using ScreenCaptureKit and saves as PNG. Requires Screen Recording permission. Prints the output file path on success. With `--json`, outputs path, window_id, width, and height.

## Examples

```sh
window-tool preview 0
window-tool preview 0 --output ~/screenshot.png
window-tool --json preview title="Browser"

# Chaining: preview inherits the selector from focus
window-tool focus 0 + preview --output ~/screenshot.png
```
