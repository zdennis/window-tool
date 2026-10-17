# window-tool fullscreen

Enter macOS fullscreen mode for a window.

## Usage

```sh
window-tool [--app <name-or-id>] fullscreen <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Details

Enters native macOS fullscreen mode (the window gets its own Space). This is different from `maximize`, which fills the visible screen area without entering fullscreen mode.

Use `unfullscreen` to exit fullscreen mode.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
window-tool --app Safari fullscreen 0
window-tool --app Safari fullscreen title="Safari"

# Chaining: fullscreen inherits the selector from focus
window-tool --app Safari focus 0 + fullscreen
```
