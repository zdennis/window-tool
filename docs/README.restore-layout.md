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

Reads a layout file and matches each saved window to a current one by window ID, then by title, then by index. The index match is a last resort and can pick an unrelated window that now sits at that index; prefer layouts with window IDs. A window is matched at most once, and layouts saved before window IDs were recorded match by title and index. Saved windows that can't be matched (e.g., the window was closed) are skipped and listed as `Warning: no window matches saved '<title>' (index N, id=ID); skipped` on stderr. The bundle ID is read from the layout file, so `--app` is not needed.

Prints how many windows were restored out of the total saved.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings, including one per unmatched saved window; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool restore-layout ~/layouts/iterm.json
# Restored 3/4 window(s) for com.googlecode.iterm2
```
