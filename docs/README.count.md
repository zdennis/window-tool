# window-tool count

Print the number of windows for an application.

## Usage

```sh
window-tool --app <name-or-bundle-id> count
```

## Details

Prints the window count as a plain integer. Requires `--app`; without it, or if the application is not running, it exits 1 with an error. With `--json`, outputs `{"count": N}`.

## Examples

```sh
window-tool --app Safari count
# 5

window-tool --app com.apple.Safari --json count
# {"count": 5}
```
