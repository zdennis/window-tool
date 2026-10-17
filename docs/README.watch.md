# window-tool watch

Watch for window changes and print updates.

## Usage

```sh
window-tool --app <name-or-id> watch [--interval <seconds>]
```

## Options

| Option | Description |
|--------|-------------|
| `--interval <seconds>` | Poll interval in seconds, greater than 0 (default: 1.0) |

## Details

Prints the current window state, then polls for changes at the given interval. When a change is detected (position, size, title, or window ID), prints the updated state (a window whose ID changed counts too) separated by `---`. With `--json`, outputs JSON arrays without the separator; each window object has `bundle_id` and, when the window has one, `window_id`.

`--interval` is the canonical form. A bare number (`watch 0.5`) is still accepted as the interval, but not together with `--interval`.

Runs until interrupted with Ctrl-C.

## Examples

```sh
window-tool --app Safari watch
window-tool --app Safari watch --interval 0.5
window-tool --app Safari --json watch --interval 2

# Legacy form
window-tool --app Safari watch 0.5
```
