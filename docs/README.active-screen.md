# window-tool active-screen

Print the bounds of the screen where the mouse cursor is.

## Usage

```sh
window-tool active-screen
```

## Details

Outputs tab-separated values: x, y, width, height. Coordinates use top-left origin, suitable for window positioning. With `--json`, outputs a JSON object.

## Examples

```sh
window-tool active-screen
# 0    0    5120    2129
```
