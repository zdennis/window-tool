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

## Examples

```sh
window-tool minimize 0
window-tool minimize title="Notes"

# Chaining: minimize inherits the selector from highlight
window-tool highlight 0 + minimize
```
