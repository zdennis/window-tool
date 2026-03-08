# window-tool info

Show detailed info for a single window, including minimized, fullscreen, and focus state.

## Usage

```sh
window-tool [--app <name-or-id>] info <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command. |

## Details

Prints tab-separated key-value pairs: index, window_id, title, position, size, role, subrole, focused, main, minimized, fullscreen, modal, and document (if available). With `--json`, outputs a JSON object.

## Examples

```sh
window-tool info 0
window-tool info id=1341
window-tool info title="my-project"
window-tool --json info 0

# Chaining: info inherits the selector from focus
window-tool focus 0 + info
```
