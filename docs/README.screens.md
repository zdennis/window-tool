# window-tool screens

List all displays with their bounds.

## Usage

```sh
window-tool screens
```

## Details

Lists all connected displays with their index, frame origin, frame size, visible origin, visible size, and flags (`main` for the primary display, `mouse` for the display containing the cursor).

Output is tab-separated. Coordinates use top-left origin. With `--json`, outputs a JSON array of screen objects.

## Examples

```sh
window-tool screens
# 0    0,0    5120x2160    0,0    5120x2129 [main,mouse]
# 1    -3840,560    3840x1600    -3840,560    3840x1600
```
