# window-tool move

Move and optionally resize a window.

## Usage

```sh
window-tool [--app <name-or-id>] move <window> <x> <y> [<width> <height>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command; in a chain, two or four numbers are read as `<x> <y> [<width> <height>]`. |
| `<x>` | Yes | Target x position |
| `<y>` | Yes | Target y position |
| `<width>` | No | New width (must be paired with height) |
| `<height>` | No | New height (must be paired with width) |

## Details

If width and height are omitted, only the position changes. If provided, the window is both moved and resized. When using `title=<pattern>`, operates on all matching windows.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari move 0 100 50
window-tool --app Safari move 0 100 50 1200 900
window-tool --app Notes move title="my-notes" 0 0 1400 1000
window-tool move id=1341 100 50

# Chaining: move inherits the selector from focus
window-tool --app Safari focus 0 + move 100 50
window-tool --app Safari focus 0 + move 100 50 1200 900
```
