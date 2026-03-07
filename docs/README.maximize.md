# window-tool maximize / maximize-by-title

Maximize a window to fill the visible screen area.

## Usage

```sh
window-tool [--app <bundle-id>] maximize <index>
window-tool [--app <bundle-id>] maximize-by-title <pattern>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (maximize) | Window index (from `list`) |
| `<pattern>` | Yes (maximize-by-title) | Substring to match against window titles |

## Details

Moves and resizes the window to fill the visible screen area (excluding menu bar and dock) on whichever screen the window currently occupies. `maximize-by-title` operates on all matching windows.

This is not macOS fullscreen mode — see `fullscreen` for that.

## Examples

```sh
window-tool maximize 0
window-tool maximize-by-title "Terminal"
```
