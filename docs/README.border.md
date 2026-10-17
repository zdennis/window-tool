# window-tool border

Add a persistent border overlay that tracks a window's position and size.

## Usage

```sh
window-tool [--app <name-or-id>] border <window> [--color <color>] [--width <pixels>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--color <color>` | Border color (default: blue) |
| `--width <pixels>` | Border width in pixels (default: 3) |

## Details

Runs as a background process that draws a border around the window and updates it as the window moves or resizes. The border process exits automatically if the window closes. With `id=<N>`, `--app` is optional: the border follows the window, including sheets and dialogs, and is filed under the app that owns it. Use `unborder` to remove the border, or `unborder-all` to remove all borders.

## Examples

```sh
window-tool --app Safari border 0
window-tool --app Safari border 0 --color red --width 5
window-tool --app Terminal border title="Terminal" --color green
window-tool border id=1341

# Chaining: border inherits the selector from focus
window-tool --app Safari focus 0 + border --color red
```
