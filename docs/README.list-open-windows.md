# window-tool list-open-windows

List all applications that currently have open windows.

## Usage

```sh
window-tool list-open-windows
```

## Details

Lists every running application that has at least one window, showing its bundle identifier. Useful for discovering the `--app` bundle ID for a target application.

With `--json`, outputs a JSON array of objects with bundle ID, app name, and window count.

## Examples

```sh
window-tool list-open-windows
# com.googlecode.iterm2    iTerm2    3
# com.apple.Safari         Safari    5
```
