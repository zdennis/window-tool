# window-tool commands

List every command, or dump the command table as JSON.

## Usage

```sh
window-tool commands
window-tool --json commands
```

## Details

Without `--json`, prints each command with its one-line summary. With `--json`, prints one object generated from the same table that drives `help`, so it cannot drift from what the tool accepts:

| Key | Description |
|-----|-------------|
| `version` | The `window-tool` version |
| `commands` | One object per command (below) |
| `enums` | Valid values for the main enum-like arguments: `snapPositions`, `colors`, `shells` |

Each entry in `commands` has:

| Key | Description |
|-----|-------------|
| `name`, `group`, `summary` | Command name, help group (Query, Move/size, Layout, Overlays, Capture, Meta) and one-line summary |
| `synopsis` | Positional arguments as shown in the usage line, such as `<window> [offset] [count] [delay]` |
| `app` | `required`, `optional` (index and title selectors need `--app`; `id=` finds the app itself) or `none` (the command ignores `--app`) |
| `mutates` | True when the command moves, resizes, focuses, minimizes or otherwise changes windows (`shake` included). Overlay commands such as `highlight`, `border` and `dim` are `false` because they leave windows unchanged |
| `accessibility` | True when the command needs Accessibility permission |
| `arguments`, `flags` | Arrays of `{name, description}` objects; `flags` are the options listed under "Options" in `help <command>` |

## Examples

```sh
window-tool commands
window-tool --json commands | jq -r '.commands[] | select(.mutates) | .name'
window-tool --json commands | jq '.enums.snapPositions'
```
