# window-tool restore-layout

Restore window positions and sizes from a previously saved layout file.

## Usage

```sh
window-tool restore-layout <file>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<file>` | Yes | Path to a layout JSON file (from `save-layout`) |

## Details

Reads a layout file and matches windows by title. Windows that can't be matched (e.g., the window was closed) are skipped. The bundle ID is read from the layout file, so `--app` is not needed.

Prints how many windows were restored out of the total saved.

## Examples

```sh
window-tool restore-layout ~/layouts/iterm.json
# Restored 3/4 window(s) for com.googlecode.iterm2
```
