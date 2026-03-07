# window-tool fullscreen / fullscreen-by-title

Enter macOS fullscreen mode for a window by index or title.

## Usage

```sh
window-tool [--app <bundle-id>] fullscreen <index>
window-tool [--app <bundle-id>] fullscreen-by-title <pattern>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (fullscreen) | Window index (from `list`) |
| `<pattern>` | Yes (fullscreen-by-title) | Substring to match against window titles |

## Details

Enters native macOS fullscreen mode (the window gets its own Space). This is different from `maximize`, which fills the visible screen area without entering fullscreen mode.

Use `unfullscreen` to exit fullscreen mode.

## Examples

```sh
window-tool fullscreen 0
window-tool fullscreen-by-title "Safari"
```
