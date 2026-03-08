# window-tool fullscreen

Enter macOS fullscreen mode for a window.

## Usage

```sh
window-tool [--app <name-or-id>] fullscreen <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |

## Details

Enters native macOS fullscreen mode (the window gets its own Space). This is different from `maximize`, which fills the visible screen area without entering fullscreen mode.

Use `unfullscreen` to exit fullscreen mode.

## Examples

```sh
window-tool fullscreen 0
window-tool fullscreen title="Safari"
```
