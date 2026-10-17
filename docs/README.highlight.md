# window-tool highlight

Briefly highlight a window with a colored border that auto-dismisses.

## Usage

```sh
window-tool [--app <name-or-id>] highlight <window> [--color <color>] [--duration <seconds>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command, unless this command names a different `--app`. |

## Options

| Option | Description |
|--------|-------------|
| `--color <color>` | Border color (default: red) |
| `--duration <seconds>` | How long to show the highlight, 0 to 86400; 0 dismisses it at once (default: 3.0) |

## Details

Draws a glowing border around the window for the specified duration, then removes it automatically. The process blocks until the highlight dismisses.

## Examples

```sh
window-tool --app Safari highlight 0
window-tool --app Safari highlight 0 --color blue --duration 5
window-tool --app Safari highlight title="Important" --color yellow

# Chaining: highlight inherits the selector from snap
window-tool --app Safari snap 0 center + highlight --color red
```
