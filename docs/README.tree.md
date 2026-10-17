# window-tool tree

Print a window's accessibility element tree: each element's path, role, title, value, frame and actions. Agents can read what a window shows without a screenshot.

## Usage

```sh
window-tool [--app <name-or-id>] tree <window> [--depth N] [--max-value N]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<window>` | Yes | Window selector: index, `id=<N>`, or `title=<pattern>` (case-insensitive; fails when several windows match unless `--first` is given). Optional when chaining with `+` -- inherits the selector from the previous command. |

## Options

| Option | Description |
|--------|-------------|
| `--depth N` | Levels below the window to show, 0 to 100 (default: 10). `--depth 0` shows only the window. |
| `--max-value N` | Cut string values to N characters, 0 for no limit (default: 200). |

## Details

The window is the root. Each element has these keys. Apart from `path` and `actions`, a key is left out when the app does not report it or reports an empty string:

| Key | Description |
|-----|-------------|
| `path` | The element's address: its child indexes from the window, dot-separated, such as `0.2.1` (child 1 of child 2 of the window's child 0). The window's own path is `""`. Always present. |
| `role`, `subrole` | Accessibility role and subrole, such as `AXButton` and `AXCloseButton` |
| `title` | The element's title |
| `description` | The accessibility description; buttons without a title often have one |
| `identifier` | The developer-assigned `AXIdentifier`, stable across launches when the app sets it |
| `value` | A string, number or boolean value (text field contents, checkbox state); other kinds of value are left out |
| `value_truncated` | `true` when `value` was cut to `--max-value` characters |
| `secure` | `true` for a password field (role or subrole `AXSecureTextField`) and for every element inside one; their `value` is never shown |
| `x`, `y`, `width`, `height` | The element's frame in screen points, top-left origin, the same coordinates as `info` |
| `actions` | Action names such as `AXPress` and `AXShowMenu`. Always an array, empty when there are none. |
| `children` | Child elements, in the app's order |
| `children_omitted` | The number of children not shown because `--depth` stopped there; given instead of `children` |
| `window_id` | On the root only: the window's ID |

An element without `children` is a leaf, or was cut off by `--depth`; check `children_omitted` to tell which.

A path is valid only until the window's UI changes: opening a tab or a menu, or a list scrolling, can shift the indexes. Read the tree again before using an old path. `text --path 0.2.1` reads the text at and below one element; the planned `press` command will take a path the same way.

AppKit custom actions are reported as `Name:<name>\nTarget:<pointer>\nSelector:<selector>`. `--json` keeps the full string, which is the name to use when performing the action; the pointer changes between launches. Text output shows only the name.

`--json` prints the root element as one nested JSON object; it is the form to parse. In a chain it is the command's `data` (`jq '.results[]'`).

Text output prints one line per element, indented two spaces per level. Each line except the window's starts with the element's `[path]`, then `role:subrole`, `window_id` (window only), `title`, `description`, `identifier`, `value`, `secure` (password fields), `frame` and `actions`, and `children_omitted` when `--depth` stopped there. Strings are quoted and cut to 80 characters; line breaks, quotes, control characters and bidi embedding, override and isolate controls are escaped. When any element has `children_omitted`, a hint to raise `--depth` goes to stderr.

```text
AXWindow:AXStandardWindow  window_id=420  title="Untitled"  frame=889,126 759x974  actions=AXRaise
  [0] AXGroup  frame=889,185 759x915  children_omitted=1
  [1] AXStaticText  value="Ready"  frame=896,166 364x17
  [2] AXButton:AXCloseButton  frame=897,138 16x16  actions=AXPress
  [3] AXCheckBox  title="Wrap lines"  value=true  frame=920,138 80x16  actions=AXPress
```

`tree` only reads the window; it does not change anything. Large windows, such as web pages, can have thousands of elements; lower `--depth` to keep the output short, and raise it where an element shows `children_omitted`.

## Examples

```sh
window-tool tree id=2457
window-tool tree id=2457 --depth 3
window-tool --app Safari tree 0 --depth 0
window-tool --json tree id=2457 --max-value 0
window-tool --json tree id=2457 | jq -c '.. | objects | select(.role? == "AXButton") | {path, name: (.title // .description)}'

# Chaining: tree inherits the selector from focus
window-tool --app TextEdit focus 0 + tree --depth 2
window-tool --json --app TextEdit focus 0 + tree --depth 2 | jq '.results[1].data'
```
