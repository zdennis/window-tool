# window-tool snap

Snap a window to a predefined screen region.

## Usage

```sh
window-tool [--app <name-or-id>] snap <window> <position>
window-tool [--app <name-or-id>] snap <window> --rect=<x,y,w,h>
window-tool [--app <name-or-id>] snap <window> --grid=<cols>x<rows> --cell=<col>,<row> [--span=<cols>,<rows>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command; in a chain, a lone position is read as `<position>`. |
| `<position>` | Yes, unless `--rect` or `--grid` is given | Snap position (see below) |

## Options

| Option | Description |
|--------|-------------|
| `--rect=<x,y,w,h>` | Snap to a region given as four fractions of the visible frame, origin at the top left, instead of a position. `x` and `y` must be at least 0, `w` and `h` greater than 0, and `x+w` and `y+h` at most 1. Giving a position or `--grid` as well is an error. |
| `--grid=<cols>x<rows>` | Divide the visible frame into a grid, such as `6x4`, and snap to the cells given by `--cell` and `--span`. `--cell` is required. Giving a position or `--rect` as well is an error. |
| `--cell=<col>,<row>` | With `--grid`, the column and row of the region's top-left cell, counting from 0 at the top left. |
| `--span=<cols>,<rows>` | With `--grid`, the region's width and height in cells (default: `1,1`). The region must fit inside the grid: `col+cols` at most the grid's columns and `row+rows` at most its rows. |

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

`--grid` is the same region counted in cells: `--grid=6x4 --cell=1,0 --span=2,3` starts one sixth of the way across the top edge and is two columns wide and three rows tall, the same as `--rect=0.1667,0,0.3333,0.75`. Cells count from 0, like window indexes. A bad grid, cell or span fails with `invalid_value` (exit 2) before any window moves, with the flag in `details.name`. `--grid` without `--cell`, or `--cell` or `--span` without `--grid`, fails with `option_required`. `--rect` and `--grid` are alternatives: giving both fails with `unexpected_argument` and `details.conflicts_with: "--grid"`.

Region edges are rounded to whole points, so adjacent regions such as neighbouring grid cells or `left-third` and `center-third` share an edge with no gap.

## Examples

```sh
window-tool --app Safari snap 0 left
window-tool --app Safari snap 1 top-right
window-tool --app Terminal snap title="Terminal" maximize
window-tool --app Safari snap 0 left-third
window-tool --app Safari snap 1 right-two-thirds
window-tool --app Safari snap 0 --rect=0,0,0.7,1
window-tool --app Safari snap 0 --grid=6x4 --cell=1,0 --span=2,3
window-tool --app Safari snap 0 --grid=3x2 --cell=2,1   # bottom-right sixth

# Chaining: snap inherits the selector from focus
window-tool --app Safari focus 0 + snap center
```
