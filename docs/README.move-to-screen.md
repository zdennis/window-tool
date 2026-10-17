# window-tool move-to-screen

Move a window to a different display.

## Usage

```sh
window-tool [--app <name-or-id>] move-to-screen <window> <screen>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command, unless this command names a different `--app`; in a chain, a lone number is read as `<screen>`. |
| `<screen>` | Yes | Target display: an index from `screens`, or `primary`, `external`, `left`, `right`, `next`, `prev` |

## Details

Moves the window to the top-left of the visible area on the target screen. Use `screens` to see available display indices.

Names are resolved when the command runs, so scripts need not call `screens` first and do not depend on display order. `primary` is display 0 (the one with the menu bar at 0,0). `external` is the first display that is not the primary. `left` and `right` are the nearest display on that side of the window's current display, by horizontal position. `next` and `prev` step from the window's current display through the indexes from `screens`, wrapping around. `left`, `right` and `external` fail with exit code 2 when no such display exists; an unknown name fails with `unknown_choice` listing the accepted values.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
window-tool --app Safari move-to-screen 0 1
window-tool --app Safari move-to-screen 0 external
window-tool --app Safari move-to-screen 0 next
window-tool --app Terminal move-to-screen title="Terminal" 0

# Chaining: move-to-screen inherits the selector from focus
window-tool --app Safari focus 0 + move-to-screen 1
```
