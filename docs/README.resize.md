# window-tool resize

Resize a window without changing its position.

## Usage

```sh
window-tool [--app <name-or-id>] resize <window> <width> <height>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |
| `<width>` | Yes | New width |
| `<height>` | Yes | New height |

## Details

When using `title=<pattern>`, operates on all matching windows.

## Examples

```sh
window-tool resize 0 1200 900
window-tool resize title="my-notes" 1400 1000
window-tool resize id=1341 800 600
```
