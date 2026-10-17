# window-tool restore

Restore (unminimize) all minimized windows for an application.

## Usage

```sh
window-tool [--app <name-or-id>] restore
```

## Details

Finds all minimized windows for the target application and restores them. Prints the number of windows restored.

## Examples

```sh
window-tool --app Safari restore
# Restored 2 window(s)
```
