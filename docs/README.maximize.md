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

Moves and resizes the window to fill the visible screen area (excluding menu bar and dock) on whichever screen the window currently occupies. When using `title=<pattern>`, operates on all matching windows.

This is not macOS fullscreen mode -- see `fullscreen` for that.

## Examples

```sh
window-tool maximize 0
window-tool maximize title="Terminal"

# Chaining: maximize inherits the selector from focus
window-tool focus 0 + maximize
```
