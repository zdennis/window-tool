# window-tool doctor

Report the version and whether the permissions window-tool needs are granted.

## Usage

```sh
window-tool doctor
window-tool doctor --json
```

## Details

Checks Accessibility (needed by every command that reads or changes windows) and Screen Recording (needed by `preview` and `record`). It never needs either permission itself, and exits 0 whether or not they are granted, so read the result rather than the exit code.

Without `--json`, prints the version, then one `granted` or `missing` line per permission. With `--json` (anywhere on the command line), prints one object:

| Key | Description |
|-----|-------------|
| `version` | The `window-tool` version |
| `accessibility` | True when Accessibility is granted |
| `screen_recording` | True when Screen Recording is granted |

`window-tool --json --version` prints just `{"version": ...}`.

## Examples

```sh
window-tool doctor
window-tool --json doctor | jq -e .accessibility >/dev/null || echo "grant Accessibility first"
```
