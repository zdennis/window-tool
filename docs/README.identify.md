# window-tool identify

Show window IDs as overlays on all visible windows. Useful for discovering window IDs to use with other commands.

## Usage

```sh
window-tool [--app <name-or-id>] identify [--color <color>] [--duration <seconds>]
```

## Options

| Option | Description |
|--------|-------------|
| `--color <color>` | Overlay color (default: magenta) |
| `--duration <seconds>` | How long to show the overlays (default: 3.0) |

## Details

Displays a labeled overlay centered on each window showing its `id=<N>` value. The overlays auto-dismiss after the specified duration.

When used without `--app`, identify shows IDs for all windows across all applications. When `--app` is provided, it only shows IDs for that application's windows.

## Examples

```sh
# Show IDs on all windows for 3 seconds
window-tool identify

# Show IDs for Safari windows only
window-tool --app Safari identify

# Custom color and duration
window-tool identify --color blue --duration 5
```
