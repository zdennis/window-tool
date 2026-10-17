# window-tool flash

Flash a colored overlay on a window as a visual notification.

## Usage

```sh
window-tool [--app <name-or-id>] flash <window> [--color <color>] [--count <N>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--color <color>` | Overlay color (default: green) |
| `--count <N>` | Number of flashes, greater than 0 (default: 1) |

## Details

Displays a translucent colored overlay on the window that fades out. Useful for confirming an action completed or drawing brief attention to a window.

## Examples

```sh
window-tool --app Safari flash 0
window-tool --app Safari flash 0 --color red --count 3
window-tool --app Safari flash title="Alert" --color yellow

# Chaining: flash inherits the selector from focus
window-tool --app Safari focus 0 + flash --color green
```
