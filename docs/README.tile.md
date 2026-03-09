# window-tool tile

Arranges windows in an automatically calculated grid layout with gaps between them.

## Usage

```sh
window-tool [--app <name-or-id>] tile [<window>...] [options]
window-tool [--app <name-or-id>] tile --untile
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>...` | No | Window selectors to tile. If omitted, tiles all windows for the app |

## Options

| Option | Description |
|--------|-------------|
| `--gap N` | Gap between windows in pixels (default: 10) |
| `--cols N` | Force a specific number of columns |
| `--untile` | Restore windows to their pre-tile positions |
| `--help`, `-h` | Show command-specific help |

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

Before tiling, all window positions and sizes are snapshotted to `/tmp/window-tool-tile-snapshot.json`. Use `--untile` to restore windows to their original layout.

All windows are tiled onto the screen containing the first window in the list.

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
window-tool --app iTerm tile --untile

# Tile by window IDs
window-tool --app iTerm tile id=1341 id=1342 id=1343
```
