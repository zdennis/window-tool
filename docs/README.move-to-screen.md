# window-tool move-to-screen

Move a window to a different display.

## Usage

```sh
window-tool [--app <name-or-id>] move-to-screen <window> <screen>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |
| `<screen>` | Yes | Target screen index (from `screens`) |

## Details

Moves the window to the top-left of the visible area on the target screen. Use `screens` to see available display indices.

## Examples

```sh
window-tool move-to-screen 0 1
window-tool move-to-screen title="Terminal" 0
```
