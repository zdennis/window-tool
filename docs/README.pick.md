# window-tool pick

Click a window to print its ID.

## Usage

```sh
window-tool pick
```

## Details

Waits for a left click anywhere on screen, finds the frontmost window under the pointer, and prints `id=<N>` (or `{"window_id": N}` with `--json`). Use the result as a selector in other commands, for example `window-tool info id=1341`. Because `id=` selectors detect the owning app, `--app` is not needed.

Press the mouse button on the window you want; the prompt `Click on a window to get its ID...` is printed to stderr so stdout holds only the ID.

Only normal windows, floating panels and modal panels (window layers 0, 3 and 8) are picked. Clicks on the menu bar, the Dock and status items are skipped: no command can resolve their IDs. If the click lands on none of these, `pick` prints `No pickable window at click location (menu bar, Dock and status items are skipped)` to stderr and exits 4 (`no_pickable_window`). Floating and modal-panel IDs may not resolve through the Accessibility API in other commands.

`pick` blocks until you click and does not need an `--app`.

## Examples

```sh
window-tool pick
# id=1341

window-tool --json pick
# {"window_id": 1341}

window-tool info "$(window-tool pick)"
```
