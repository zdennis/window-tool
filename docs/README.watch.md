# window-tool watch

Watch for window changes and print updates.

## Usage

```sh
window-tool --app <name-or-id> watch [interval]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[interval]` | No | Poll interval in seconds, greater than 0 (default: 1.0) |

## Details

Prints the current window state, then polls for changes at the given interval. When a change is detected (position, size, or title), prints the updated state separated by `---`. With `--json`, outputs JSON arrays without the separator.

Runs until interrupted with Ctrl-C.

## Examples

```sh
window-tool --app Safari watch
window-tool --app Safari watch 0.5
window-tool --app Safari --json watch 2
```
