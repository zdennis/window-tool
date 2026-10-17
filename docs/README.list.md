# window-tool list

List windows with their app, index, position, size, and title.

## Usage

```sh
window-tool list
window-tool --app <name-or-id> list
window-tool list [--title <glob>] [--screen <screen>] [--visible] [--no-minimized] [--sort app|title|id]
```

## Details

Without `--app`, lists all windows across all running applications, sorted by app name. With `--app`, lists only windows for that application.

Text output columns (tab-separated): APP, BUNDLE_ID, INDEX, WID, POSITION, SIZE, TITLE. With `--json`, outputs a JSON array of windows in the `info` schema (bundle_id, index or parent_index, window_id, title, x, y, width, height, minimized, fullscreen, focused, main, modal, role, subrole, document) plus `app`, `pid`, `screen`, `on_screen` and `layer`. `screen` is the index of the display (as in `screens`) containing the window's center, left out when the window is off every display. `on_screen` is false for minimized windows and windows on other Spaces. `layer` is the window level (0 for normal windows). `window_id`, `pid`, `screen`, `on_screen` and `layer` are left out when unknown, so use `// empty` or `.field? // null` in `jq`. The text output is unchanged and has no state columns; use `--json` to filter on them.

## Filters and sorting

Filters combine with AND and apply to text and `--json` output alike. An empty result prints just the header (or `[]`).

| Option | Keeps |
|---|---|
| `--title <glob>` | Windows whose whole title matches the glob (`*`, `?`, `[a-z]`), ignoring case. Use `*PR*` to match a substring. |
| `--screen <screen>` | Windows whose center is on that display. Takes an index from `screens`, or `primary`, `external`, `left`, `right`, `next`, `prev`; the relative names are relative to the display holding the mouse. Windows on no display never match. |
| `--visible` | Windows that are on screen: not minimized and on the current Space. Windows with no window ID are left out. |
| `--no-minimized` | Windows that are not minimized (windows on other Spaces stay). |
| `--sort <key>` | `app` (default, by app name), `title` (case-insensitive) or `id` (window ID, windows without one last). |

An unknown `--sort` key or `--screen` name exits 2 (`unknown_choice`). A `--screen` index that does not exist, or `external`, `left` or `right` with no such display, exits 2 as well. `--title` is a whole-title glob, unlike the substring match of the `title=` selector, so `--title PR` matches only a window titled exactly `PR`.

## Examples

```sh
window-tool list
# APP       BUNDLE ID                INDEX  WID   POSITION   SIZE        TITLE
# iTerm2    com.googlecode.iterm2    0      1341  100,50     1200x900    ~/projects
# Safari    com.apple.Safari         0      1502  200,100    800x600     GitHub

window-tool --app iTerm list
window-tool --json list
window-tool list --title='*PR*' --screen=1 --visible --no-minimized --sort=title
window-tool --app Safari --json list --no-minimized --sort=id
window-tool --json list | jq '.[] | select(.minimized | not) | .window_id'
```
