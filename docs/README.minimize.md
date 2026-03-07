# window-tool minimize / minimize-by-title

Minimize a window to the dock by index or title.

## Usage

```sh
window-tool [--app <bundle-id>] minimize <index>
window-tool [--app <bundle-id>] minimize-by-title <pattern>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (minimize) | Window index (from `list`) |
| `<pattern>` | Yes (minimize-by-title) | Substring to match against window titles |

## Details

Minimizes the window to the dock. Use `restore` to unminimize all minimized windows.

## Examples

```sh
window-tool minimize 0
window-tool minimize-by-title "Notes"
```
