# window-tool info

Show detailed info for a single window by index, including minimized and fullscreen state.

## Usage

```sh
window-tool [--app <bundle-id>] info <index>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes | Window index (from `list`) |

## Details

Prints tab-separated key-value pairs: index, title, position, size, minimized, and fullscreen. With `--json`, outputs a JSON object.

## Examples

```sh
window-tool info 0
# index:     0
# title:     My Window
# position:  100,50
# size:      1200x900
# minimized: false
# fullscreen: false

window-tool --json info 0
```
