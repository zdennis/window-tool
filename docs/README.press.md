# window-tool press

Press a button, or perform another accessibility action, on one element of a window. Agents can click a control by its path or its role and title, without a screenshot or a synthetic mouse click.

## Usage

```sh
window-tool [--app <name-or-id>] press <window> [--path <path>] [--role <role>] [--title <title>] [--action <action>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

At least one of `--path`, `--role` and `--title` is required.

| Option | Description |
|--------|-------------|
| `--path <path>` | The element at this path, as `tree` prints it, such as `0.2.1`. With `--role` or `--title`, search at and below it instead. `""`, the default, is the whole window. |
| `--role <role>` | Only an element with exactly this role, such as `AXButton`. |
| `--title <title>` | Only an element whose whole title is this, ignoring case. Unlike the `title=` window selector, it is not a substring: `Save` does not match `Save As…`. |
| `--action <action>` | The action to perform, as `tree` lists it under `actions`, such as `AXShowMenu` or `AXIncrement` (default: `AXPress`). For an AppKit custom action, the raw string from `tree --json` or just its name works. |

## Details

`press` finds one element and calls `AXUIElementPerformAction` on it. It sends no mouse or keyboard events, so the window does not need to be in front.

With only `--path`, it acts on the element at that path. With `--role` or `--title`, it searches the element at `--path` and everything below it, up to 100 levels, and needs exactly one match. When several elements match, it fails with `ambiguous_element` and lists their paths. Toolbar buttons often have a `description` but no `title`; use `--path` for those.

A path is valid only until the window's UI changes. Read `tree` again before using an old one, or guard it: `--path 0.2 --role AXButton --title Save` presses the Save button only if it is still at or below `0.2`, and fails with `no_matching_element` otherwise.

Password fields (role or subrole `AXSecureTextField`) and every element inside one are never acted on. A `--path` that points at one fails with `secure_element`, and a `--role`/`--title` search never matches one.

Success means the app accepted the action, not that it did what you expected. An app that is showing a modal dialog can ignore presses on its other windows. Read the result back with `text` or `tree`; `wait` watches windows, not their contents, so poll `text` or `tree` for a change inside one. When the app does not answer in time, `press` exits 0 with a warning that the app did not confirm the action, and `element.confirmed` is `false`. A button that opens a modal dialog does this after running, but a hung app returns the same error without running it, so after such a warning check `confirmed` or `warnings` and read the window again.

With `--json`, prints the window in the `info` schema and any warnings, as other mutating commands do (see [Mutating command results](../README.md#mutating-command-results)), plus `element`: the `path`, `role` and `title` (each left out when absent) of the element it acted on, the raw `action`, and `confirmed`, `false` when the app did not answer in time. `windows` is empty when the action closed the window. `press` adds nothing to the `undo` history.

```sh
$ window-tool press id=811 --role AXButton --title save
Performed AXPress on [0] AXButton title="Save"
$ window-tool press id=811 --title Dup
Error: 2 elements match with title "Dup":
  [1] AXButton title="Dup"
  [2] AXButton title="Dup"
Add --role to narrow it, or use --path with one of the paths above.
```

Errors:

- `option_required` (exit 2): none of `--path`, `--role` and `--title` was given.
- `invalid_value` (exit 2): a malformed path, as for `text`, or an empty `--action`.
- `no_element_at_path` (exit 4): a path past the end of an element's children. `details` gives `path`, the `parent` path, its child `count` and `window_id`.
- `no_matching_element` (exit 4): no element matches `--role`/`--title`. `details` gives `path` (where the search started), `role` and `title` (each only when given) and `window_id`.
- `ambiguous_element` (exit 4): several elements match. `details` gives the same keys plus `matches`, each with `path` and, when the element has them, `role` and `title`.
- `secure_element` (exit 1): the element is a password field or inside one. `details` gives `path` and `window_id`.
- `action_not_supported` (exit 1): the element does not offer the action. `details` gives `action`, `path`, the element's `actions` and `window_id`.
- `operation_failed` (exit 1): the app refused the action; the message gives the AXError.

## Examples

```sh
window-tool press id=2457 --role AXButton --title Save
window-tool press id=2457 --path 0.2.1
window-tool press id=2457 --path 0.3 --title OK
window-tool press id=2457 --path 0.2 --role AXButton --title Save   # fails if the UI moved
window-tool press id=2457 --path 0.4 --action AXShowMenu
window-tool --json press id=2457 --title Save | jq '.element.path'

# Find a button's path with tree, then press it
path=$(window-tool --json tree id=2457 | jq -r 'first(.. | objects | select(.role? == "AXButton" and .description? == "Back") | .path)')
window-tool press id=2457 --path "$path"

# Chaining: press inherits the selector, then text reads the result
window-tool press id=2457 --title Save + text --path 0.5
```

See also [tree](README.tree.md) for paths, roles and actions, and [text](README.text.md) to read the result.
