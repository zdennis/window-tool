# window-tool stack

Cascade windows with a fixed offset between each.

## Usage

```sh
window-tool --app <name-or-id> stack [<window>...] [--offset N]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>...` | No | Window selectors to cascade: index, `id=<N>`, or `title=<pattern>`. If omitted, cascades all windows for the app |

## Options

| Option | Description |
|--------|-------------|
| `--offset N` | Pixel offset between each window (default: 30) |

## Details

Positions the windows in a cascade starting from the top-left of the screen, with each subsequent window offset down and to the right by the offset. Selected windows are cascaded in the order given.

`--offset` is the canonical form. For compatibility, a lone bare number with no `--offset` and no other arguments is still read as the offset (`stack 50`), not as a window index. To cascade a single window by index, use `--offset` or a `title=`/`id=` selector.

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized and any warnings; see [Mutating command results](../README.md#mutating-command-results).

## Examples

```sh
window-tool --app Safari stack
window-tool --app Safari stack --offset 50
window-tool --app Safari stack 0 1 2 --offset 40
window-tool --app Safari stack title="Inbox" title="Drafts"

# Legacy form
window-tool --app Safari stack 50
```
