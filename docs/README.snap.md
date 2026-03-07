# window-tool snap / snap-by-title

Snap a window to a predefined screen region by index or title.

## Usage

```sh
window-tool [--app <bundle-id>] snap <index> <position>
window-tool [--app <bundle-id>] snap-by-title <pattern> <position>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (snap) | Window index (from `list`) |
| `<pattern>` | Yes (snap-by-title) | Substring to match against window titles |
| `<position>` | Yes | Snap position (see below) |

## Details

Positions the window on the screen where it currently resides, using the visible area (excluding the menu bar and dock).

Available positions: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `center`, `maximize`.

- `left`/`right` — half-width, full-height
- `top`/`bottom` — full-width, half-height
- Corner positions — half-width, half-height
- `center` — keeps current size, centers on screen
- `maximize` — fills the entire visible screen area

## Examples

```sh
window-tool snap 0 left
window-tool snap 1 top-right
window-tool snap-by-title "Terminal" maximize
```
