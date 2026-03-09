# window-tool sidebar

Pins a window to the left or right edge of its screen as a sidebar, with optional push/unpush of other windows.

## Usage

```sh
window-tool [--app <name-or-id>] sidebar <window> [--side=left|right] [--full-height] [--push]
window-tool sidebar --unpush
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes (except with `--unpush`) | Window selector (index, `id=N`, or `title=pattern`) |

## Options

| Option | Description |
|--------|-------------|
| `--side=left` | Pin to the left edge (default) |
| `--side=right` | Pin to the right edge |
| `--full-height` | Maximize the window height to fill the visible screen area |
| `--push` | Push all overlapping windows on the same screen away from the sidebar |
| `--unpush` | Restore all windows to their pre-push positions and sizes |

## Details

The window is moved to the specified edge of the screen while keeping its current width. Without `--full-height`, the window also keeps its current height and is positioned at the top of the screen.

With `--full-height`, the window is resized to fill the full visible screen height (excluding the menu bar and dock).

### Push behavior

When `--push` is used, after placing the sidebar window, all other windows on the same screen that overlap with the sidebar are pushed away. Windows are pushed horizontally (right for a left sidebar, left for a right sidebar). If pushing a window would move it partially off-screen, its width is reduced to keep it on-screen. All window positions and sizes are snapshotted before any pushing occurs.

### Unpush behavior

`--unpush` reads the snapshot saved by `--push` and restores every window to its original position and size. The snapshot is then deleted. If no snapshot exists, an error message is printed and the command exits with code 1.

The snapshot covers windows from all applications, not just the `--app` target.

## Examples

```sh
# Pin window 0 to the left edge
window-tool --app Notes sidebar 0

# Pin to the right edge
window-tool --app Notes sidebar 0 --side=right

# Pin to the left edge and fill screen height
window-tool --app Notes sidebar 0 --side=left --full-height

# Pin as sidebar and push other windows out of the way
window-tool --app Notes sidebar 0 --side=left --full-height --push

# Restore all windows to their pre-push positions
window-tool sidebar --unpush

# Pin by window ID
window-tool --app Notes sidebar id=1341 --full-height

# Chain: sidebar then highlight
window-tool --app Notes sidebar 0 --full-height + highlight --color blue
```
