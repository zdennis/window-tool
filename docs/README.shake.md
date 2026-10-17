# window-tool shake

Shake a window to draw attention to it.

## Usage

```sh
window-tool [--app <name-or-id>] shake <window> [offset] [count] [delay]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command; in a chain, bare numbers are read as `[offset] [count] [delay]` unless four are given, so name another window with `id=` or `title=`. |
| `[offset]` | No | Shake distance in pixels (default: 12) |
| `[count]` | No | Number of shakes, greater than 0 (default: 6) |
| `[delay]` | No | Delay between movements in seconds (default: 0.04) |

## Details

Rapidly moves the window left and right to draw attention to it, then returns it to its original position.

## Examples

```sh
window-tool --app Safari shake 0
window-tool --app Safari shake 0 20 4 0.05
window-tool --app Safari shake title="Alert" 15

# Chaining: shake inherits the selector from focus
window-tool --app Safari focus 0 + shake

# Chaining: bare numbers are shake arguments, so this shakes window 0 by 20px
window-tool --app Safari focus 0 + shake 20
```
