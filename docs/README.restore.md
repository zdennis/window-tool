# window-tool restore

Restore (unminimize) minimized windows for an application, or one specific window.

## Usage

```sh
window-tool --app <name-or-id> restore
window-tool [--app <name-or-id>] restore <window>
```

## Details

Without a selector, finds all minimized windows for the target application and restores them; in a chain, a bare `restore` still restores all and does not inherit the previous selector. With a window selector (`<index>`, `id=<N>` or `title=<pattern>`), restores only that window; `id=` needs no `--app`. A selected window that is not minimized is left alone (the count is 0). Prefer `id=` in scripts, since indexes can shift after a window is minimized. Prints the number of windows restored (without `--json`).

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari restore
# Restored 2 window(s)

window-tool --app Safari restore 1
# Restored 1 window(s)

window-tool restore id=1687
```
