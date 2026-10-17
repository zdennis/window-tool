# window-tool focus

Bring a window to the front.

## Usage

```sh
window-tool [--app <name-or-id>] focus <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Details

Activates the application and raises the specified window to the front.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
window-tool --app Safari focus 0
window-tool focus id=1341
window-tool --app Safari focus title="my-project"

# Chaining: focus inherits the selector from snap
window-tool --app Safari snap 0 center + focus
```
