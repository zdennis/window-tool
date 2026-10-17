# window-tool snap

Snap a window to a predefined screen region.

## Usage

```sh
window-tool [--app <name-or-id>] snap <window> <position>
window-tool [--app <name-or-id>] snap <window> --rect=<x,y,w,h>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command; in a chain, a lone position is read as `<position>`. |
| `<position>` | Yes, unless `--rect` is given | Snap position (see below) |

## Options

| Option | Description |
|--------|-------------|
| `--rect=<x,y,w,h>` | Snap to a region given as four fractions of the visible frame, origin at the top left, instead of a position. `x` and `y` must be at least 0, `w` and `h` greater than 0, and `x+w` and `y+h` at most 1. Giving a position as well is an error. |

## Details

Positions the window on the screen where it currently resides, using the visible area (excluding the menu bar and dock).

Available positions: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `center`, `maximize`, `left-third`, `center-third`, `right-third`, `left-two-thirds`, `right-two-thirds`.

- `left`/`right` -- half-width, full-height
- `top`/`bottom` -- full-width, half-height
- Corner positions -- half-width, half-height
- `left-third`/`center-third`/`right-third` -- one-third width, full-height
- `left-two-thirds`/`right-two-thirds` -- two-thirds width, full-height, anchored to the left or right edge
- `center` -- keeps current size, centers on screen
- `maximize` -- fills the entire visible screen area

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

`--rect` uses the same visible area, so the result is the same on any display size: `--rect=0,0,0.7,1` is the left 70%, `--rect=0.5,0.5,0.5,0.5` the bottom-right quarter. Fractions are relative to the screen the window is on.

## Examples

```sh
window-tool --app Safari snap 0 left
window-tool --app Safari snap 1 top-right
window-tool --app Terminal snap title="Terminal" maximize
window-tool --app Safari snap 0 left-third
window-tool --app Safari snap 1 right-two-thirds
window-tool --app Safari snap 0 --rect=0,0,0.7,1

# Chaining: snap inherits the selector from focus
window-tool --app Safari focus 0 + snap center
```
