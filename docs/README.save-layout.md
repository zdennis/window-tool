# window-tool save-layout

Save the windows of every running app, or of one app with `--app`, as a named layout or to a JSON file.

## Usage

```sh
window-tool save-layout <name-or-file>
window-tool --app <name-or-id> save-layout <name-or-file>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<name-or-file>` | Yes | A layout name such as `coding`, saved as `~/.config/window-tool/layouts/coding.json`, or a file path. An argument containing `/` or ending in `.json` is a path; anything else is a name and may use letters, digits, `.`, `_` and `-`, not starting with `.` |

## Details

Without `--app`, every running app's windows go into one layout; with `--app`, only that app's. Saving to an existing name or file replaces it.

A bare word such as `coding` is always a named layout. To write a file in the current directory, use `./coding` or `coding.json`. Before named layouts, `save-layout coding` wrote `./coding`. Run `layouts` to see the named layouts and `restore-layout <name>` to put the windows back.

Each window is saved with its app's bundle ID, index, window ID, title, position and size. It also gets the UUID of the display holding its center (`screen_uuid`, the `uuid` in `screens --json`) and its frame as fractions of that display's visible frame (`fraction`: `x`, `y`, `width`, `height` from 0 to 1, origin top left). `restore-layout` uses the fractions, so a layout still fits after a resolution change or a Dock resize. A window whose center is on no display has neither field. Like `list`, untitled windows without a window ID are left out, because nothing could match them again.

A layout saved with `--app` also keeps the bundle ID at the top of the file, as layouts did before they covered every app.

Prints `Saved N window(s) to <file>`, with the full path for a named layout. With `--json`, it prints the saved layout with its `path` added instead; `window_id`, `screen_uuid` and `fraction` are left out for a window that has none.

## Examples

```sh
window-tool save-layout coding
# Saved 9 window(s) to /Users/me/.config/window-tool/layouts/coding.json

window-tool --app iTerm save-layout ~/layouts/iterm.json
window-tool --app com.apple.Safari save-layout safari.json
```
