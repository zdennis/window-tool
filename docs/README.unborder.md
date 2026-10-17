# window-tool unborder

Remove border overlays for the target application.

## Usage

```sh
window-tool [--app <name-or-id>] unborder [<window>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | No | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). |

## Details

Without a window selector, removes all borders on windows owned by the target application. With a selector, removes only the border for that specific window; `id=<N>` needs no `--app`. Borders are filed under the app that owns the window, so the no-selector form needs `--app` to name that app; use `unborder-all` otherwise. See also `unborder-all` to remove all borders across all applications.

## Examples

```sh
window-tool --app Safari unborder
window-tool --app Safari unborder 0
window-tool unborder id=1341

# Chaining: unborder inherits the selector from the previous command
window-tool --app Safari focus 0 + unborder
```
