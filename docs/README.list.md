# window-tool list

List all windows with their index, position, size, and title.

## Usage

```sh
window-tool [--app <bundle-id>] list
```

## Details

Output is tab-separated: index, position (x,y), size (widthxheight), and title. With `--json`, outputs a JSON array of window objects.

## Examples

```sh
window-tool list
# 0    100,50    1200x900    My Window Title
# 1    200,100   800x600     Another Window

window-tool --json list
```
