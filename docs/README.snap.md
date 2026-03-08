# window-tool snap

Snap a window to a predefined screen region.

## Usage

```sh
window-tool [--app <name-or-id>] snap <window> <position>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |
| `<position>` | Yes | Snap position (see below) |

## Details

Positions the window on the screen where it currently resides, using the visible area (excluding the menu bar and dock).

Available positions: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `center`, `maximize`.

- `left`/`right` -- half-width, full-height
- `top`/`bottom` -- full-width, half-height
- Corner positions -- half-width, half-height
- `center` -- keeps current size, centers on screen
- `maximize` -- fills the entire visible screen area

## Examples

```sh
window-tool snap 0 left
window-tool snap 1 top-right
window-tool snap title="Terminal" maximize

# Chaining: snap inherits the selector from focus
window-tool focus 0 + snap center
```
