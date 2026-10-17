# window-tool maximize

Maximize a window to fill the visible screen area.

## Usage

```sh
window-tool [--app <name-or-id>] maximize <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |

## Details

Moves and resizes the window to fill the visible screen area (excluding menu bar and dock) on whichever screen the window currently occupies. When using `title=<pattern>`, operates on all matching windows (case-insensitive substring match).

This is not macOS fullscreen mode -- see `fullscreen` for that.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
window-tool --app Safari maximize 0
window-tool --app Terminal maximize title="Terminal"

# Chaining: maximize inherits the selector from focus
window-tool --app Safari focus 0 + maximize
```
