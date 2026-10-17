# window-tool screens

List all displays with their bounds.

## Usage

```sh
window-tool screens
```

## Details

Lists all connected displays with their index, frame origin, frame size, visible origin (excluding the menu bar and Dock), visible size, backing scale factor, and flags (`main` for the display holding the focused window, which is not always the primary display at 0,0; `mouse` for the display containing the cursor).

Output is tab-separated. Coordinates are in the same global top-left system `list`, `info` and `move` use, with the origin at the top-left of the primary display, so a display above the primary has a negative y. `scale` is the backing scale factor (2 on Retina), the ratio of `preview` pixels to these point coordinates. Earlier versions reported `frame_y` and `visible_y` in bottom-left coordinates and had no `scale`; text output gained a SCALE column before FLAGS, so parse `--json` rather than splitting columns. With `--json`, outputs a JSON array of objects with `index`, `frame_x`, `frame_y`, `frame_width`, `frame_height`, `visible_x`, `visible_y`, `visible_width`, `visible_height`, `scale`, `uuid`, `main` and `mouse`. `uuid` is the display's stable UUID (it survives reconnects and reboots, unlike `index`) and is `null` if macOS reports none; it is JSON-only, and `active-screen --json` includes it too.

## Examples

```sh
window-tool screens
# INDEX  FRAME_ORIGIN  FRAME_SIZE  VISIBLE_ORIGIN  VISIBLE_SIZE  SCALE  FLAGS
# 0      0,0           5120x2160   0,34            5120x2126     2.0    [main,mouse]
# 1      -3840,560     3840x1600   -3840,560       3840x1600     2.0
```
