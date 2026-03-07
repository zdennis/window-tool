# window-tool save-layout

Save the current window layout for an application to a JSON file.

## Usage

```sh
window-tool [--app <bundle-id>] save-layout <file>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<file>` | Yes | Path to save the layout JSON file |

## Details

Captures the index, title, position, and size of every window for the target application and writes them to a JSON file. Use `restore-layout` to restore the saved positions later.

The JSON format includes the bundle ID and an array of window snapshots, making layout files portable across sessions.

## Examples

```sh
window-tool save-layout ~/layouts/iterm.json
window-tool --app com.apple.Safari save-layout ~/layouts/safari.json
```
