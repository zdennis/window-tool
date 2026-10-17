# window-tool active-screen

Print the usable bounds of the screen where the mouse cursor is.

## Usage

```sh
window-tool active-screen
```

## Details

Outputs tab-separated values: x, y, width, height. The rectangle is the screen's visible area (excluding the menu bar and Dock), in the same global top-left coordinates that `move` and `info` use, so it works on secondary displays and with a left- or right-side Dock. With `--json`, outputs the screen's full `screens` entry (see [screens](README.screens.md)): `index`, frame and visible rectangles, `scale`, `main` and `mouse`. Use the `visible_*` fields where earlier versions returned `x`, `y`, `width` and `height`.

## Examples

```sh
window-tool active-screen
# X    Y     WIDTH    HEIGHT
# 0    34    1728     1083

window-tool --json active-screen
# {"index": 0, "frame_x": 0, "frame_y": 0, "frame_width": 1728, "frame_height": 1117,
#  "visible_x": 0, "visible_y": 34, "visible_width": 1728, "visible_height": 1083,
#  "scale": 2, "main": true, "mouse": true}
```
