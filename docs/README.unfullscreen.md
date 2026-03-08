# window-tool unfullscreen

Exit macOS fullscreen mode for a window.

## Usage

```sh
window-tool [--app <name-or-id>] unfullscreen <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |

## Details

Exits native macOS fullscreen mode, returning the window to its previous size and position.

## Examples

```sh
window-tool unfullscreen 0
window-tool unfullscreen title="Safari"

# Chaining: unfullscreen inherits the selector from a previous command
window-tool focus 0 + unfullscreen
```
