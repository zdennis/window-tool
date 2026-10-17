# window-tool wait

Block until a window exists, or with `--gone` until it is gone.

## Usage

```sh
window-tool [--app <name-or-id>] wait <window> [--gone] [--stable <seconds>] [--timeout <seconds>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive substring). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--gone` | Wait for the window to disappear instead of appear. Cannot be combined with `--stable`. |
| `--stable <seconds>` | Also wait until the window's position and size have not changed for this long, greater than 0. |
| `--timeout <seconds>` | Give up after this long, greater than 0 (default: 30). |

## Details

Polls every 0.1 seconds. Exit code 0 means the condition held; exit code 7 (error code `timeout`, `details.waiting_for` and `details.timeout` under `--json`) means it did not before the timeout. Other failures keep their usual codes, such as 2 for a missing `--app` with an index or `title=` selector.

On success the matched window is printed as `info` prints it (a JSON object under `--json`, with `bundle_id`). With `--gone` it prints `Gone: <window>`, or `{"gone": true}` under `--json`.

The app does not have to be running yet: `--app` is looked up on every poll, so `wait` can follow a launch. A mistyped app name therefore waits for the whole timeout instead of failing at once. An ambiguous `--app` still fails immediately (exit 3).

`title=` succeeds when at least one window matches and reports the first, so it never fails as ambiguous. Selectors that name a window by index only mean "the window at that position right now". Prefer `id=` or `title=` in scripts.

With `--gone`, a window that never existed counts as gone, so the command exits 0 at once.

In a chain, the selector is inherited by the next command, pinned to the window's ID once found: `wait title=Doc --app TextEdit + snap left`. After `--gone` the inherited selector names a window that no longer exists, so give the next command its own selector. With `--stable` and a `title=` that matches several windows, the first match is used on each poll, so prefer `id=` there.

## Examples

```sh
window-tool --app Safari wait title="Pull Request" --timeout 10
window-tool wait id=2457 --gone --timeout 5
window-tool wait id=2457 --stable 0.3
window-tool --app TextEdit wait title=Doc + snap left
window-tool --json --app Safari wait title=Inbox | jq .window_id
```
