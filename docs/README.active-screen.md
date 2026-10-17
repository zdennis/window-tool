# window-tool active-screen

Print the usable bounds of the screen where the mouse cursor is.

## Usage

```sh
window-tool active-screen
```

## Details

Outputs tab-separated values: x, y, width, height. The rectangle is the screen's visible area (excluding the menu bar and Dock), in the same global top-left coordinates that `move` and `info` use, so it works on secondary displays and with a left- or right-side Dock. With `--json`, outputs a JSON object.

## Examples

```sh
window-tool active-screen
# X    Y     WIDTH    HEIGHT
# 0    34    1728     1083
```
