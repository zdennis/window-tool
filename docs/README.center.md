# window-tool center

Centers a window on its current screen, optionally resizing it first.

## Usage

```sh
window-tool [--app <name-or-id>] center <window> [--size=N or --size=W,H]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector (index, `id=N`, or `title=pattern`) |

## Options

| Option | Description |
|--------|-------------|
| `--size=N` | Resize to NxN pixels before centering |
| `--size=W,H` | Resize to W x H pixels before centering |
| `--size=WxH` | Resize to W x H pixels before centering (alternate delimiter) |

## Details

Without `--size`, the window is centered using its current dimensions. When `--size` is provided, the window is resized first, then centered on the screen's visible area.

The command uses the screen that currently contains the window to determine centering bounds.

## Examples

```sh
# Center window 0 on its current screen
window-tool --app Safari center 0

# Center and resize to 800x800
window-tool --app Safari center 0 --size=800

# Center and resize to 1200x900
window-tool --app Safari center 0 --size=1200,900
window-tool --app Safari center 0 --size=1200x900

# Center by window ID
window-tool --app Safari center id=1341 --size=1000

# Chain: center then highlight
window-tool --app Safari center 0 --size=1000 + highlight --color green
```
