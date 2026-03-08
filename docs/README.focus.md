# window-tool focus

Bring a window to the front.

## Usage

```sh
window-tool [--app <name-or-id>] focus <window>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` |

## Details

Activates the application and raises the specified window to the front.

## Examples

```sh
window-tool focus 0
window-tool focus id=1341
window-tool focus title="my-project"
```
