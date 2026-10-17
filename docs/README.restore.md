# window-tool restore

Restore (unminimize) all minimized windows for an application.

## Usage

```sh
window-tool --app <name-or-id> restore
```

## Details

Finds all minimized windows for the target application and restores them. Prints the number of windows restored (without `--json`).

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari restore
# Restored 2 window(s)
```
