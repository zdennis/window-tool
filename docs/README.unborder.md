# window-tool unborder

Remove border overlays for the target application.

## Usage

```sh
window-tool [--app <name-or-id>] unborder [<window>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | No | Window selector: index, `id=<N>`, or `title=<pattern>` |

## Details

Without a window selector, removes all borders for the target application. With a selector, removes only the border for that specific window. See also `unborder-all` to remove all borders across all applications.

## Examples

```sh
window-tool unborder
window-tool unborder 0
window-tool unborder id=1341
```
