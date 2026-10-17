# window-tool close

Close a window, or every window of an app.

## Usage

```sh
window-tool [--app <name-or-id>] close <window>
window-tool --app <name-or-id> close --all
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes, unless `--all` | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--all` | Close every window of `--app` instead of one window. Takes no window selector. |

## Details

Presses the window's close button (`AXCloseButton`) and waits up to 2 seconds for the window to go. Exit code 0 means the window is gone.

A document with unsaved changes answers with a sheet ("Do you want to save changes?") and stays open. `close` then fails with exit code 6 and error code `unsaved_changes`, listing the windows (`details.windows` under `--json`, each with `window_id` and `title`, so you can retry with `close id=<N>`). It never answers the sheet; deal with it in the app and run `close` again. With `--all`, the other windows are still closed and the error lists the ones that asked; it takes precedence over a plain failure, so run `close --all` again to see any others. An app with no windows fails with `no_windows` (exit 4).

A window with no close button, or one that is still open after the wait, fails with `operation_failed` (exit 1).

Closing cannot be undone, and `close --all` takes every window of the app, so check with `list` first. `--json` prints `{"windows": [], "warnings": []}` because closed windows no longer exist to be re-read; see [Mutating command results](../README.md#mutating-command-results). `--verbose` adds nothing: the `Closed N window(s)` line already confirms it.

## Examples

```sh
window-tool --app Preview close 0
window-tool close id=2457
window-tool --app Slack close title="Huddle"
window-tool --app Preview close --all
```
