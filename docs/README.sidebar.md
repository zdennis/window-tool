# window-tool sidebar

Pins a window to the left or right edge of its screen as a sidebar.

## Usage

```sh
window-tool [--app <name-or-id>] sidebar <window> [--side=left|right] [--full-height]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector (index, `id=N`, or `title=pattern`) |

## Options

| Option | Description |
|--------|-------------|
| `--side=left` | Pin to the left edge (default) |
| `--side=right` | Pin to the right edge |
| `--full-height` | Maximize the window height to fill the visible screen area |

## Details

The window is moved to the specified edge of the screen while keeping its current width. Without `--full-height`, the window also keeps its current height and is positioned at the top of the screen.

With `--full-height`, the window is resized to fill the full visible screen height (excluding the menu bar and dock).

## Examples

```sh
# Pin window 0 to the left edge
window-tool --app Notes sidebar 0

# Pin to the right edge
window-tool --app Notes sidebar 0 --side=right

# Pin to the left edge and fill screen height
window-tool --app Notes sidebar 0 --side=left --full-height

# Pin by window ID
window-tool --app Notes sidebar id=1341 --full-height

# Chain: sidebar then highlight
window-tool --app Notes sidebar 0 --full-height + highlight --color blue
```
