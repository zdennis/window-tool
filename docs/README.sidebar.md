# window-tool sidebar

Pins a window to an edge of its screen as a sidebar, with optional push/unpush of other windows.

## Usage

```sh
window-tool [--app <name-or-id>] sidebar <window> [--side left|right|top|bottom] [options]
window-tool sidebar --unpush
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes (except with `--unpush`) | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). |

## Options

| Option | Description |
|--------|-------------|
| `--side left` | Pin to the left edge (default) |
| `--side right` | Pin to the right edge |
| `--side top` | Pin to the top edge |
| `--side bottom` | Pin to the bottom edge |
| `--full-height` | Maximize the window height to fill the visible screen area |
| `--full-width` | Maximize the window width to fill the visible screen area |
| `--push` | Push all overlapping windows on the same screen away from the sidebar |
| `--unpush` | Undo the last `sidebar`: restore the sidebar window and any windows it pushed |

`--side=right` and the other `--flag=value` spellings work too.

## Details

The window is moved to the specified edge of the screen while keeping its current dimensions. Use `--full-height` or `--full-width` to expand the window along the pinned edge.

### Push behavior

When `--push` is used, after placing the sidebar window, all other windows on the same screen that overlap with the sidebar are pushed away:

- **Left/right sidebars** push windows horizontally
- **Top/bottom sidebars** push windows vertically

If pushing a window would move it partially off-screen, its width or height is reduced to keep it on-screen. Windows without a window ID are not pushed, because `--unpush` could not find them again.

### Unpush behavior

Every `sidebar` saves the previous frames of the windows it moved, the sidebar window and pushed windows from any app, in the undo history. `--unpush` reverts the newest `sidebar` entry, even when other changes came after it, and puts the sidebar window back too; `undo` reverts the newest change of any kind. See [undo](README.undo.md). With no `sidebar` in the history, `--unpush` fails with `Nothing to undo. Run 'sidebar' first.` (exit 1).

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
# Pin window 0 to the left edge
window-tool --app Notes sidebar 0

# Pin to the right edge
window-tool --app Notes sidebar 0 --side right

# Pin to the top edge, full width
window-tool --app Notes sidebar 0 --side=top --full-width

# Pin to the bottom edge, full width
window-tool --app Notes sidebar 0 --side=bottom --full-width

# Pin to the left edge and fill screen height
window-tool --app Notes sidebar 0 --side=left --full-height

# Pin as sidebar and push other windows out of the way
window-tool --app Notes sidebar 0 --side=left --full-height --push

# Undo the sidebar, putting pushed windows back
window-tool sidebar --unpush

# Pin by window ID
window-tool --app Notes sidebar id=1341 --full-height

# Chain: sidebar then highlight
window-tool --app Notes sidebar 0 --full-height + highlight --color blue
```
