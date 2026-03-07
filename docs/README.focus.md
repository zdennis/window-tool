# window-tool focus / focus-by-title

Bring a window to the front by index or title.

## Usage

```sh
window-tool [--app <bundle-id>] focus <index>
window-tool [--app <bundle-id>] focus-by-title <pattern>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<index>` | Yes (focus) | Window index (from `list`) |
| `<pattern>` | Yes (focus-by-title) | Substring to match against window titles |

## Details

Activates the application and raises the specified window to the front.

## Examples

```sh
window-tool focus 0
window-tool focus-by-title "my-project"
```
