# window-tool count

Print the number of windows for an application.

## Usage

```sh
window-tool [--app <bundle-id>] count
```

## Details

Prints the window count as a plain integer. Returns `0` if the application is not running (does not error). With `--json`, outputs `{"count": N}`.

## Examples

```sh
window-tool count
# 3

window-tool --app com.apple.Safari count
# 5
```
