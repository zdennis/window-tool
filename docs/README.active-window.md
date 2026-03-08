# window-tool active-window

Print info about the frontmost application's primary window.

## Usage

```sh
window-tool active-window [--id]
```

## Options

| Option | Description |
|--------|-------------|
| `--id` | Print only the CGWindowID instead of full info |

## Details

Reports the primary window of the currently focused application. Without `--id`, prints the same detailed info as `info` (index, window_id, title, position, size, focused, minimized, fullscreen, etc.). With `--id`, prints only the numeric CGWindowID, useful for scripting and shell integration.

## Examples

```sh
window-tool active-window
window-tool active-window --id
window-tool --json active-window
```
