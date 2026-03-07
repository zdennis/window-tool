# window-tool shake / shake-by-title

Shake a window by index or title (visual attention effect).

## Usage

```sh
window-tool [--app <bundle-id>] shake <index> [offset] [count] [delay]
window-tool [--app <bundle-id>] shake-by-title <pattern> [offset] [count] [delay]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (shake) | Window index (from `list`) |
| `<pattern>` | Yes (shake-by-title) | Substring to match against window titles |
| `[offset]` | No | Shake distance in pixels (default: 12) |
| `[count]` | No | Number of shakes (default: 6) |
| `[delay]` | No | Delay between movements in seconds (default: 0.04) |

## Details

Rapidly moves the window left and right to draw attention to it, then returns it to its original position.

## Examples

```sh
window-tool shake 0
window-tool shake 0 20 4 0.05
window-tool shake-by-title "Alert" 15
```
