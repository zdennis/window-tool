# window-tool unfullscreen / unfullscreen-by-title

Exit macOS fullscreen mode for a window by index or title.

## Usage

```sh
window-tool [--app <bundle-id>] unfullscreen <index>
window-tool [--app <bundle-id>] unfullscreen-by-title <pattern>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (unfullscreen) | Window index (from `list`) |
| `<pattern>` | Yes (unfullscreen-by-title) | Substring to match against window titles |

## Details

Exits native macOS fullscreen mode, returning the window to its previous size and position.

## Examples

```sh
window-tool unfullscreen 0
window-tool unfullscreen-by-title "Safari"
```
