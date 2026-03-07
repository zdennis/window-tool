# window-tool watch

Watch for window changes and print updates.

## Usage

```sh
window-tool [--app <bundle-id>] watch [interval]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[interval]` | No | Poll interval in seconds (default: 1.0) |

## Details

Prints the current window state, then polls for changes at the given interval. When a change is detected (position, size, or title), prints the updated state separated by `---`. With `--json`, outputs JSON arrays without the separator.

Runs until interrupted with Ctrl-C.

## Examples

```sh
window-tool watch
window-tool watch 0.5
window-tool --json watch 2
```
