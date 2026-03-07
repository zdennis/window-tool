# window-tool columnize

Arrange windows side-by-side in non-overlapping columns.

## Usage

```sh
window-tool [--app <bundle-id>] columnize <index> <index> [<index>...] [--gap N]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (2+) | Window indices to arrange (from `list`) |

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
window-tool --app com.apple.Safari columnize 0 1 2
```
