# window-tool resize / resize-by-title

Resize a window by index or title without changing its position.

## Usage

```sh
window-tool [--app <bundle-id>] resize <index> <width> <height>
window-tool [--app <bundle-id>] resize-by-title <pattern> <width> <height>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (resize) | Window index (from `list`) |
| `<pattern>` | Yes (resize-by-title) | Substring to match against window titles |
| `<width>` | Yes | New width |
| `<height>` | Yes | New height |

## Examples

```sh
window-tool resize 0 1200 900
window-tool resize-by-title "my-notes" 1400 1000
```
