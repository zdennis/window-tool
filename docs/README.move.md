# window-tool move / move-by-title

Move and optionally resize a window by index or title.

## Usage

```sh
window-tool [--app <bundle-id>] move <index> <x> <y> [<width> <height>]
window-tool [--app <bundle-id>] move-by-title <pattern> <x> <y> [<width> <height>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (move) | Window index (from `list`) |
| `<pattern>` | Yes (move-by-title) | Substring to match against window titles |
| `<x>` | Yes | Target x position |
| `<y>` | Yes | Target y position |
| `<width>` | No | New width (must be paired with height) |
| `<height>` | No | New height (must be paired with width) |

## Details

`move` operates on a single window by index. `move-by-title` operates on all windows whose title contains the given pattern.

If width and height are omitted, only the position changes. If provided, the window is both moved and resized.

## Examples

```sh
window-tool move 0 100 50
window-tool move 0 100 50 1200 900
window-tool move-by-title "my-notes" 0 0 1400 1000
```
