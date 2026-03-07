# window-tool move-to-screen / move-to-screen-by-title

Move a window to a different display by index or title.

## Usage

```sh
window-tool [--app <bundle-id>] move-to-screen <index> <screen>
window-tool [--app <bundle-id>] move-to-screen-by-title <pattern> <screen>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (move-to-screen) | Window index (from `list`) |
| `<pattern>` | Yes (move-to-screen-by-title) | Substring to match against window titles |
| `<screen>` | Yes | Target screen index (from `screens`) |

## Details

Moves the window to the top-left of the visible area on the target screen. Use `screens` to see available display indices.

## Examples

```sh
window-tool move-to-screen 0 1
window-tool move-to-screen-by-title "Terminal" 0
```
