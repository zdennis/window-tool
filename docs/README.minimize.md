# window-tool minimize

Minimize a window to the dock.

## Usage

```sh
window-tool [--app <name-or-id>] minimize <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |

## Details

Minimizes the window to the dock. Use `restore` to unminimize all minimized windows.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari minimize 0
window-tool --app Notes minimize title="Notes"

# Chaining: minimize inherits the selector from highlight
window-tool --app Safari highlight 0 + minimize
```
