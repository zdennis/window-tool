# window-tool tile

Arranges windows in an automatically calculated grid layout with gaps between them.

## Usage

```sh
window-tool --app <name-or-id> tile [<window>...] [options]
window-tool tile --untile
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>...` | No | Window selectors to tile: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). If omitted, tiles all windows for the app |

## Options

| Option | Description |
|--------|-------------|
| `--gap N` | Gap between windows in pixels (default: 10) |
| `--cols N` | Force a specific number of columns (must be greater than 0) |
| `--untile` | Undo the last `tile`: restore the windows it moved (no `--app` needed) |

## Details

The grid layout is calculated automatically based on window count:

| Windows | Grid |
|---------|------|
| 1 | 1x1 (maximize) |
| 2 | 1 row, 2 cols |
| 3-4 | 2 rows, 2 cols |
| 5-6 | 2 rows, 3 cols |
| 7-9 | 3 rows, 3 cols |
| 10-12 | 3 rows, 4 cols |

Use `--cols N` to override the automatic column count.

Tiling saves the windows' previous frames in the undo history, like every command that moves windows. `--untile` reverts the newest `tile` entry, even when other changes came after it, and `undo` reverts the newest change of any kind; see [undo](README.undo.md). With no `tile` in the history, `--untile` fails with `Nothing to undo. Run 'tile' first.` (exit 1).

All windows are tiled onto the screen containing the first window in the list.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
# Tile all windows for an app
window-tool --app iTerm tile

# Tile specific windows
window-tool --app iTerm tile 0 1 2 3

# Tile with larger gaps
window-tool --app iTerm tile --gap 20

# Force 2 columns
window-tool --app iTerm tile --cols 2

# Restore windows to pre-tile positions
window-tool tile --untile

# Tile by window IDs
window-tool --app iTerm tile id=1341 id=1342 id=1343
```
