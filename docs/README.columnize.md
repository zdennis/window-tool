# window-tool columnize

Arrange windows side-by-side in non-overlapping columns.

## Usage

```sh
window-tool [--app <name-or-id>] columnize <window> <window> [<window>...] [--gap N]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes (2+) | Window selectors to arrange: index, `id=<N>`, or `title=<pattern>` |

## Options

| Option | Description |
|--------|-------------|
| `--gap <N>` | Gap in pixels between columns (default: 10) |

## Details

Arranges the specified windows in equal-width columns across the visible screen area. Windows are placed in the order given, left to right. The application is activated and all arranged windows are raised to the front.

## Examples

```sh
window-tool columnize 0 1
window-tool columnize 0 1 2 --gap 20
window-tool --app Safari columnize 0 1 2
```
