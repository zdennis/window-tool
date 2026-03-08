# window-tool move-to-screen

Move a window to a different display.

## Usage

```sh
window-tool [--app <name-or-id>] move-to-screen <window> <screen>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |
| `<screen>` | Yes | Target screen index (from `screens`) |

## Details

Moves the window to the top-left of the visible area on the target screen. Use `screens` to see available display indices.

## Examples

```sh
window-tool move-to-screen 0 1
window-tool move-to-screen title="Terminal" 0

# Chaining: move-to-screen inherits the selector from focus
window-tool focus 0 + move-to-screen 1
```
