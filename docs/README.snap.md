# window-tool snap

Snap a window to a predefined screen region.

## Usage

```sh
window-tool [--app <name-or-id>] snap <window> <position>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command; in a chain, a lone position is read as `<position>`. |
| `<position>` | Yes | Snap position (see below) |

## Details

Positions the window on the screen where it currently resides, using the visible area (excluding the menu bar and dock).

Available positions: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `center`, `maximize`.

- `left`/`right` -- half-width, full-height
- `top`/`bottom` -- full-width, half-height
- Corner positions -- half-width, half-height
- `center` -- keeps current size, centers on screen
- `maximize` -- fills the entire visible screen area

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari snap 0 left
window-tool --app Safari snap 1 top-right
window-tool --app Terminal snap title="Terminal" maximize

# Chaining: snap inherits the selector from focus
window-tool --app Safari focus 0 + snap center
```
