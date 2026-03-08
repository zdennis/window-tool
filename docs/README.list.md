# window-tool list

List windows with their app, index, position, size, and title.

## Usage

```sh
window-tool list
window-tool --app <name-or-id> list
```

## Details

Without `--app`, lists all windows across all running applications, sorted by app name. With `--app`, lists only windows for that application.

Text output columns (tab-separated): APP, BUNDLE_ID, INDEX, WID, POSITION, SIZE, TITLE. With `--json`, outputs a JSON array with keys: app, bundle_id, index, window_id, x, y, width, height, title.

## Examples

```sh
window-tool list
# APP       BUNDLE ID                INDEX  WID   POSITION   SIZE        TITLE
# iTerm2    com.googlecode.iterm2    0      1341  100,50     1200x900    ~/projects
# Safari    com.apple.Safari         0      1502  200,100    800x600     GitHub

window-tool --app iTerm list
window-tool --json list
```
