# window-tool highlight

Briefly highlight a window with a colored border that auto-dismisses.

## Usage

```sh
window-tool [--app <name-or-id>] highlight <window> [--color <color>] [--duration <seconds>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--color <color>` | Border color (default: red) |
| `--duration <seconds>` | How long to show the highlight (default: 3.0) |

## Details

Draws a glowing border around the window for the specified duration, then removes it automatically. The process blocks until the highlight dismisses.

## Examples

```sh
window-tool highlight 0
window-tool highlight 0 --color blue --duration 5
window-tool highlight title="Important" --color yellow

# Chaining: highlight inherits the selector from snap
window-tool snap 0 center + highlight --color red
```
