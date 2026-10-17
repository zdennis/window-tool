# window-tool quit

Quit an application and wait until it has exited.

## Usage

```sh
window-tool --app <name-or-id> quit [--force]
```

## Options

| Option | Description |
|--------|-------------|
| `--force` | Force-terminate the app instead of asking it to quit. Unsaved changes are lost. |

## Details

Requires `--app`. Asks every running instance of the app to quit (`NSRunningApplication.terminate`, or `forceTerminate` with `--force`) and waits up to 5 seconds for it to exit. Exit code 0 means the app is gone. Accessibility access is not needed.

An app with unsaved documents usually answers the request with a prompt and keeps running. `quit` then fails with `operation_failed` (exit 1) and a message that says the app may be asking about unsaved changes. Answer the prompt in the app, or run `quit --force` to discard the changes. Unlike [close](README.close.md), `quit` does not look for the prompt, so it has no `unsaved_changes` error (exit 6).

Quitting cannot be undone. Without `--app` it fails with `app_required` (exit 2); if the app is not running, `app_not_found` (exit 3), which a script that only wants the app gone can treat as success. The wait is fixed at 5 seconds.

With `--json`, prints `{"quit": true, "app": "<name>", "bundle_id": "<id>", "forced": false}`. It is not a window result, so it has no `windows` list.

## Examples

```sh
window-tool --app Preview quit
window-tool --app Preview quit --force
window-tool --json --app com.apple.Preview quit
```
