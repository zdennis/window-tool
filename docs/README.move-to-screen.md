# window-tool move-to-screen

Move a window to a different display.

## Usage

```sh
window-tool [--app <name-or-id>] move-to-screen <window> <screen>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command; in a chain, a lone number is read as `<screen>`. |
| `<screen>` | Yes | Target screen index (from `screens`) |

## Details

Moves the window to the top-left of the visible area on the target screen. Use `screens` to see available display indices.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari move-to-screen 0 1
window-tool --app Terminal move-to-screen title="Terminal" 0

# Chaining: move-to-screen inherits the selector from focus
window-tool --app Safari focus 0 + move-to-screen 1
```
