# window-tool shake

Shake a window to draw attention to it.

## Usage

```sh
window-tool [--app <name-or-id>] shake <window> [offset] [count] [delay]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |
| `[offset]` | No | Shake distance in pixels (default: 12) |
| `[count]` | No | Number of shakes (default: 6) |
| `[delay]` | No | Delay between movements in seconds (default: 0.04) |

## Details

Rapidly moves the window left and right to draw attention to it, then returns it to its original position.

## Examples

```sh
window-tool shake 0
window-tool shake 0 20 4 0.05
window-tool shake title="Alert" 15
```
