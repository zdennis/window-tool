# window-tool restore-layout

Move windows back to a layout saved with `save-layout`, optionally opening apps that are not running.

## Usage

```sh
window-tool restore-layout <name-or-file> [--launch] [--dry-run]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<name-or-file>` | Yes | A layout name from `layouts`, or a path to a layout file (an argument containing `/` or ending in `.json`) |

## Options

| Option | Description |
|--------|-------------|
| `--launch` | Open the layout's apps that are not running, then wait up to 10 seconds in total for them to show as many windows as the layout saved for each |
| `--dry-run` | Print where each window would go and how it was matched, without moving anything or opening apps |

A bare word such as `coding` is always a named layout. To use a file in the current directory, write `./coding` or `coding.json`. A missing `coding.json` suggests dropping the extension to restore the layout by name.

## Details

The layout names its apps, so `--app` is not needed. Within each app, each saved window is matched to a current one by window ID, then by exact title (untitled windows never match by title), then by index. Window IDs change when an app restarts, so after a restart or `--launch` windows usually match by title. The index match is a last resort and can pick an unrelated window that now sits at that index. A window is matched at most once. A saved window with no match (for example, it was closed) is skipped with `Warning: no <bundle-id> window matches saved '<title>' (index N, id=ID); skipped` on stderr.

A window saved with a display UUID goes to the same fractions of that display's current visible frame, so it still fits after a resolution change. If that display is not connected, the window goes to the same fractions of the primary display and stderr gets one `Warning: display <uuid> is not connected; its windows go to the primary display`. Layouts saved before display UUIDs were recorded restore the saved position and size as they are.

An app that is not running is skipped with `Warning: <bundle-id> is not running; skipped N window(s). Pass --launch to open it.` When none of the layout's apps is running, the command fails with `app_not_found` (exit 3), except with `--dry-run`. With `--launch`, every missing app is opened at once, then window-tool waits until each shows as many windows as were saved for it, for at most 10 seconds in total. An app that is not installed, has not opened by then (`did not open within 10s`) or shows fewer windows (`showed N of M saved window(s) within 10s`) gets a warning, and its saved windows that find no match are skipped.

Prints `Restored N/M window(s) for <bundle-id>`, or `for K apps` when the layout covers several. A partial restore (an app not running, a window not matched) still exits 0. To detect one, compare `restored` with `total` in the `--json` result, or N with M in the text. When nothing at all was restored, stderr also gets a warning suggesting `--dry-run`. A name with no saved layout fails with `file_not_found` (exit 1), and a file that is not a layout fails with `operation_failed` (exit 1).

With `--json`, prints the changed window(s) in the `info` schema, plus `requested` for a window that was moved or resized, any warnings (including one per unmatched saved window), and the counts `restored` (saved windows that matched and were moved) and `total` (saved windows in the layout); see [Mutating command results](../README.md#mutating-command-results). Each restore is one `undo` entry.

`--dry-run` prints one row per saved window, tab-separated with a header: `APP` (bundle ID), `MATCH`, `WID` (the matched window's ID, or `-`), the target `POSITION` and `SIZE`, and the saved `TITLE`. `MATCH` is one of:

| `match` | Meaning | Moves |
|---------|---------|-------|
| `id` | Matched by window ID | Yes |
| `title` | Matched by exact title (an empty title never matches) | Yes |
| `index` | Matched by index, the last resort | Yes |
| `none` | No current window matched | No |
| `not_running` | The app is not running | No |
| `launch` | The app is not running; `--launch` would open it | Unknown until it opens |

With `--json` it prints `{"plan": [...], "warnings": [...]}`, each plan entry with `bundle_id`, `title`, `match`, `will_move` (true for `id`, `title` and `index`), `window_id` (null when unmatched) and the target `x`, `y`, `width`, `height`. The warnings are the ones a real run would print; as with every command, they also go to stderr. A dry run does not fail when none of the layout's apps is running: every row is `not_running`.

## Examples

```sh
window-tool restore-layout coding
# Restored 8/9 window(s) for 4 apps

window-tool restore-layout coding --launch
window-tool restore-layout coding --dry-run

window-tool restore-layout ~/layouts/iterm.json
# Restored 3/4 window(s) for com.googlecode.iterm2
```
