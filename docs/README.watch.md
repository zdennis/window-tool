# window-tool watch

Watch for window changes and print updates.

## Usage

```sh
window-tool --app <name-or-id> watch [--interval <seconds>] [--ndjson] [--once] [--timeout <seconds>]
```

## Options

| Option | Description |
|--------|-------------|
| `--interval <seconds>` | Poll interval in seconds, greater than 0 (default: 1.0) |
| `--ndjson` | Print one compact JSON event per line instead of full snapshots (see below) |
| `--once` | Stop after the first change; with `--timeout`, exit 7 if nothing changed in time |
| `--timeout <seconds>` | Stop watching after this long, greater than 0. Exits 0, or 7 (`timeout`) with `--once` and no change |

## Details

Prints the current window state, then polls for changes at the given interval. When a change is detected (position, size, title, or window ID), prints the updated state (a window whose ID changed counts too) separated by `---`. With `--json`, outputs JSON arrays without the separator; each window object has `bundle_id` and, when the window has one, `window_id`.

`--interval` is the canonical form. A bare number (`watch 0.5`) is still accepted as the interval, but not together with `--interval`.

Runs until interrupted with Ctrl-C, or until `--once` or `--timeout` ends it. `--once` and `--timeout` work in every mode; without `--ndjson`, `--once` stops after the first changed snapshot is printed. With `--json --once`, the starting snapshot is not printed, so the command prints exactly one JSON document: the changed snapshot (exit 0), or the `timeout` error object (exit 7).

### `--ndjson`

Prints nothing for the starting state, then one JSON object per line for each change, matched by window ID (`--json` is not needed, but errors still print as JSON only with it; windows without a window ID are not tracked and never produce events). Lines are flushed as they print, so `while read` loops and `jq -c` see them at once. In a `+` chain the events are collected into the command's `data` array instead.

| `event` | Meaning | Extra keys |
|---------|---------|------------|
| `added` | A window appeared | |
| `removed` | A window is gone (the last known state is printed) | |
| `moved` | Position or size changed | `previous`: `{x, y, width, height}` |
| `retitled` | Title changed | `previous_title` |

Every event has `event`, `bundle_id`, `window_id`, `index` (position in the app's window list at that poll; for `removed`, the last known position, so key on `window_id`), `x`, `y`, `width`, `height` and `title`. There is no event for the starting state: run `list --json` first if you need it (a window opened between the two calls is missed). One poll can produce several events for the same window (`moved` and `retitled`).

## Examples

```sh
window-tool --app Safari watch
window-tool --app Safari watch --interval 0.5
window-tool --app Safari --json watch --interval 2

# Events as they happen
window-tool --app Safari watch --ndjson | jq -c 'select(.event == "added") | .window_id'

# Block until the next change, at most 10 seconds (exit 7 on timeout)
window-tool --app Safari watch --ndjson --once --timeout 10

# Legacy form
window-tool --app Safari watch 0.5
```
