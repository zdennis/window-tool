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

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari unfullscreen 0
window-tool --app Safari unfullscreen title="Safari"

# Chaining: unfullscreen inherits the selector from a previous command
window-tool --app Safari focus 0 + unfullscreen
```
