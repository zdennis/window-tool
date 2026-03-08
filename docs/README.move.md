# window-tool move

Move and optionally resize a window.

## Usage

```sh
window-tool [--app <name-or-id>] move <window> <x> <y> [<width> <height>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |
| `<x>` | Yes | Target x position |
| `<y>` | Yes | Target y position |
| `<width>` | No | New width (must be paired with height) |
| `<height>` | No | New height (must be paired with width) |

## Details

If width and height are omitted, only the position changes. If provided, the window is both moved and resized. When using `title=<pattern>`, operates on all matching windows.

## Examples

```sh
window-tool move 0 100 50
window-tool move 0 100 50 1200 900
window-tool move title="my-notes" 0 0 1400 1000
window-tool move id=1341 100 50

# Chaining: move inherits the selector from focus
window-tool focus 0 + move 100 50
```
