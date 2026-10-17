# window-tool text

Print the text inside a window: the values of its labels and text fields, one per line. Agents can read a window's contents without a screenshot.

## Usage

```sh
window-tool [--app <name-or-id>] text <window> [--path <path>] [--focused] [--raw] [--max-value N]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--path <path>` | Read only the element at this path and its descendants. The path is the one `tree` prints, such as `0.2.1`; `""`, the default, is the whole window. |
| `--focused` | Print only the value of the element that has keyboard focus. With `--json`, print just that element's object. Fails with exit code 4 (`no_focused_element`) when nothing in the window, or under `--path`, has keyboard focus. |
| `--raw` | Print line breaks and tabs inside values as they are, so the text reads as it does in the window. Other control characters, such as ESC, stay escaped. |
| `--max-value N` | Cut values to N characters, 0 for no limit (default: 0). A cut value ends in `…` in text output and has `value_truncated: true` under `--json`. |

## Details

`text` reads the window's accessibility elements, walking up to 100 levels deep. It prints the value of every static text, text field, text area and combo box whose frame lies inside the window's frame, in `tree` order. An element with an empty frame, or one outside the window's frame, is left out, but its children are still read. Content scrolled out of a pane but still inside the window's frame is kept. By default values are not cut, so a terminal or editor prints its whole text area; use `--max-value` to cap them.

Password fields (role or subrole `AXSecureTextField`) are never shown, nor is any element inside one, whether reached from the window, through `--path`, or as the focused element. Such an element reports `secure: true` and no value; `--focused` on one prints nothing and exits 0, and `--path` to one prints nothing.

There are three output forms:

- **Default:** one value per line. Line breaks, tabs, backslashes, control characters and bidi embedding, override and isolate controls inside a value are escaped (`\n`, `\t`, `\\`, `\u{1b}`, `\u{202e}`), so each line is one element and cannot be reordered on screen.
- **`--raw`:** values with their real line breaks and tabs, each followed by a newline. Every other character escaped by default stays escaped, except backslashes and quotes. A value with several lines can no longer be told from several values.
- **`--json`:** the exact strings. Use `--json | jq -r` to get them for a script.

`--json` prints one object:

| Key | Description |
|-----|-------------|
| `window_id` | The window's ID, left out when it has none |
| `path` | The `--path` given, `""` for the whole window |
| `texts` | One object per value, in `tree` order: `path` (the element's `tree` path), `role`, `value` (always a string) and `value_truncated` when cut |
| `focused` | The element with keyboard focus when it is in the window and at or below `path`, otherwise `null`. It has `path`, `role`, `value`, `value_truncated` and `secure`. `value` can be a string, number or boolean (a focused slider or checkbox), and is left out when the element has none or is, or is inside, a password field. |

`texts` entries carry no frame; use `tree --json` for where an element is.

Keyboard focus belongs to the app, not the window: when another window of the same app is focused, this window has no focused element. In text output, `--focused` prints nothing when the focused element has no value; use `--json` to tell that from an empty field.

A path is valid only until the window's UI changes; run `tree` again before using an old one.

Errors:

- `no_element_at_path` (exit 4): a path past the end of an element's children. `details` gives `path`, the `parent` path, its child `count` and `window_id`.
- `no_focused_element` (exit 4): nothing has keyboard focus. `details` gives `window_id` (`null` when the window has none) and `path`.
- `invalid_value` (exit 2): a malformed path. Only whole numbers as `tree` prints them are accepted, so `01`, `+1` and `0..1` fail.

`text` only reads the window; it does not change anything.

```sh
$ window-tool text id=420
Ready
Hello\nworld
$ window-tool text id=420 --raw
Ready
Hello
world
$ window-tool --json text id=420 --focused
{
  "path" : "0.0.5.0",
  "role" : "AXTextArea",
  "value" : "Hello\nworld"
}
```

## Examples

```sh
window-tool text id=2457
window-tool text id=2457 --raw
window-tool text id=2457 --path 0.1
window-tool text id=2457 --focused --raw
window-tool text id=2457 --max-value 200
window-tool --json text id=2457 | jq -r '.texts[].value'
window-tool --json text id=2457 | jq -r '.focused.value // empty'

# Find an element with tree, then read the text under it
window-tool --json tree id=2457 | jq -r '.. | objects | select(.role? == "AXScrollArea") | .path'
window-tool text id=2457 --path 0.2

# Chaining: text inherits the selector from focus
window-tool --app TextEdit focus 0 + text
```
