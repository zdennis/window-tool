# window-tool resize

Resize a window without changing its position.

## Usage

```sh
window-tool [--app <name-or-id>] resize <window> <width> <height>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>`. Optional when chaining with `+` -- inherits the selector from the previous command, unless this command names a different `--app`; in a chain, two numbers are read as `<width> <height>`. |
| `<width>` | Yes | New width |
| `<height>` | Yes | New height |

## Details

When using `title=<pattern>`, operates on all matching windows (case-insensitive substring match).

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results). Without `--json`, `--verbose` prints one line per changed window.

## Examples

```sh
window-tool --app Safari resize 0 1200 900
window-tool --app Notes resize title="my-notes" 1400 1000
window-tool resize id=1341 800 600

# Chaining: resize inherits the selector from focus
window-tool --app Safari focus 0 + resize 800 600
```
