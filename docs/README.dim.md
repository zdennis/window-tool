# window-tool dim

Dim everything on screen except a specified window.

## Usage

```sh
window-tool [--app <name-or-id>] dim <window> [--opacity <value>] [--duration <seconds>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |

## Options

| Option | Description |
|--------|-------------|
| `--opacity <value>` | Dim overlay opacity, 0.0-1.0 (default: 0.5) |
| `--duration <seconds>` | Auto-dismiss after this many seconds; 0 means stay until `undim` (default: 0) |

## Details

Creates a dark overlay across all screens with a cutout for the target window, drawing focus to it. Only one dim overlay can be active at a time; starting a new one replaces the previous. Use `undim` to remove it, or set `--duration` for auto-dismiss.

## Examples

```sh
window-tool dim 0
window-tool dim 0 --opacity 0.7 --duration 10
window-tool dim title="Important" --opacity 0.3
```
