# window-tool shake

Shake a window to draw attention to it.

## Usage

```sh
window-tool [--app <name-or-id>] shake <window> [--offset N] [--count N] [--delay <seconds>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command; with legacy positional values (see Details), bare numbers in a chain are read as `[offset] [count] [delay]` unless four are given, so name another window with `id=` or `title=`. |

## Options

| Option | Description |
|--------|-------------|
| `--offset N` | Shake distance in pixels (default: 12) |
| `--count N` | Number of shakes, greater than 0 (default: 6) |
| `--delay <seconds>` | Delay between movements in seconds (default: 0.04) |

## Details

Rapidly moves the window left and right to draw attention to it, then returns it to its original position.

The options are the canonical form. For compatibility, `[offset] [count] [delay]` are still accepted as positionals after the window (`shake 0 20 4 0.05`), but not together with any option. Once an option is given, a bare number is only the window selector, so `+ shake --count 3` shakes the inherited window and `shake 2 --count 3` shakes window 2.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
window-tool --app Safari shake 0
window-tool --app Safari shake 0 --offset 20 --count 4 --delay 0.05
window-tool --app Safari shake title="Alert" --offset 15

# Legacy positional form
window-tool --app Safari shake 0 20 4 0.05

# Chaining: shake inherits the selector from focus
window-tool --app Safari focus 0 + shake

# Chaining: named options keep the inherited window
window-tool --app Safari focus 0 + shake --offset 20

# Chaining: with the legacy form, bare numbers are shake arguments, so this also shakes window 0 by 20px
window-tool --app Safari focus 0 + shake 20
```
