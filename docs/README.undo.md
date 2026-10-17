# window-tool undo

Reverts the last command that moved or resized windows, or shows the undo history.

## Usage

```sh
window-tool undo [--steps N]
window-tool undo --list
```

## Options

| Option | Description |
|--------|-------------|
| `--steps N` | Revert the last N changes, newest first (default: 1, must be greater than 0) |
| `--list` | Show the undo history, newest first, without changing anything |

`--steps=3` works too.

## Details

Every command that moves or resizes windows (`move`, `resize`, `snap`, `center`, `maximize`, `move-to-screen`, `tile`, `columnize`, `stack`, `sidebar`, `restore-layout`) saves the frames it replaced as one entry in the undo history. `undo` puts those windows back and removes the entry. A command in a `+` chain is its own entry, and a command that fails partway still saves the windows it already moved.

A window is recorded only if it has a window ID and ended up somewhere other than where it started, so `shake` adds nothing and a command that changed nothing leaves the history as it was. `focus`, `minimize`, `restore`, `fullscreen`, `unfullscreen` and `close` are not recorded. `undo` itself is not recorded either, so running it twice reverts two changes; there is no redo.

The history keeps the last 20 entries in `window-tool-undo-history.json` in your per-user temporary directory (`$TMPDIR`), so it is cleared on restart. Windows are found again by window ID; a window that has closed since is skipped with a warning (`Warning: 'Notes' (id=1341) no longer exists; not restored`) and the exit code stays 0. The entry is removed from the history even when some of its windows could not be restored; each of those windows is reported as a warning.

With an empty history, `undo` fails with `nothing_to_undo` (exit 1). `--steps` larger than the history fails with `invalid_value` (exit 2) before anything moves.

`tile --untile` and `sidebar --unpush` are aliases that revert the newest `tile` or `sidebar` entry, even when other changes came after it; that entry is removed and the rest of the history stays. Because they put back the frames from that entry, a window moved again since then also jumps back to where it was before the `tile` or `sidebar`.

With `--json`, `undo` prints the windows it restored in the `info` schema, plus `requested` and any warnings; see [Mutating command results](../README.md#mutating-command-results). `undo --list --json` prints `{"entries": [...]}`, each entry with `step` (1 is what a plain `undo` reverts), `command`, `arguments`, `time` (ISO 8601, UTC) and `windows` (`bundle_id`, `window_id`, `title` and the saved `x`, `y`, `width`, `height`). The text form is tab-separated with a header: `STEP`, `TIME` (local), `WINDOWS` (count) and `COMMAND`. Without `--json`, `--verbose` adds one `Undid …` line per window after the `Undid …` summary.

## Examples

```sh
window-tool --app Safari snap 0 left
window-tool undo
# Undid 'snap 0 left': restored 1 window(s)

window-tool undo --list
# STEP	TIME	WINDOWS	COMMAND
# 1	2026-10-17 10:02:00	3	tile --gap 5
# 2	2026-10-17 10:01:00	1	move id=1341 0 0

# Revert the last three changes
window-tool undo --steps 3
```
