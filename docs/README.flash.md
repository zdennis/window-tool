# window-tool flash

Flash a colored overlay on a window as a visual notification.

## Usage

```sh
window-tool [--app <name-or-id>] flash <window> [--color <color>] [--count <N>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |

## Options

| Option | Description |
|--------|-------------|
| `--color <color>` | Overlay color (default: green) |
| `--count <N>` | Number of flashes (default: 1) |

## Details

Displays a translucent colored overlay on the window that fades out. Useful for confirming an action completed or drawing brief attention to a window.

## Examples

```sh
window-tool flash 0
window-tool flash 0 --color red --count 3
window-tool flash title="Alert" --color yellow
```
