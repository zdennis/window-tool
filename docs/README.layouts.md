# window-tool layouts

List the named layouts saved with `save-layout <name>`.

## Usage

```sh
window-tool layouts
```

## Details

Lists every `.json` file in `~/.config/window-tool/layouts/` by name, sorted ignoring case. The text output is tab-separated with a header: `NAME`, `WINDOWS` (the number saved), `APPS` (bundle IDs, comma-separated) and `SAVED` (the file's modification time, local). With no saved layouts it prints only the header, and stderr gets `No saved layouts. Save one with 'window-tool save-layout <name>'.`

With `--json`, it prints an array of objects with `name`, `path`, `windows` (count), `apps` (array of bundle IDs) and `saved` (ISO 8601, UTC), or `[]` with no saved layouts.

A file in the directory that is not a layout is skipped with `Warning: <path> is not a window-tool layout; skipped` on stderr. Layouts saved to a path outside the directory are not listed. To delete a layout, remove its file (the `path` in `--json`), for example `rm ~/.config/window-tool/layouts/coding.json`.

Does not need Accessibility access.

## Examples

```sh
window-tool layouts
# NAME	WINDOWS	APPS	SAVED
# coding	9	com.googlecode.iterm2,com.apple.Safari,md.obsidian	2026-10-17 10:02:00

window-tool restore-layout "$(window-tool --json layouts | jq -r '.[0].name')"
```
