# window-tool minimize

Minimize a window to the dock.

## Usage

```sh
window-tool [--app <name-or-id>] minimize <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |

## Details

Minimizes the window to the dock. Use `restore` to unminimize all minimized windows.

## Examples

```sh
window-tool minimize 0
window-tool minimize title="Notes"
```
