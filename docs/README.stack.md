# window-tool stack

Cascade all windows with a fixed offset between each.

## Usage

```sh
window-tool [--app <name-or-id>] stack [offset]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[offset]` | No | Pixel offset between each window (default: 30) |

## Details

Positions all windows in a cascade starting from the top-left of the screen, with each subsequent window offset down and to the right by the specified amount.

## Examples

```sh
window-tool --app Safari stack
window-tool --app Safari stack 50
```
