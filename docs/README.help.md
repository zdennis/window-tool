# window-tool help

Show all commands, or one command's arguments and options.

## Usage

```sh
window-tool help [<command>]
window-tool <command> --help
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<command>` | No | Command to describe. Without it, prints every command grouped as Query, Move/size, Layout, Overlays, Capture and Meta, followed by selectors, options and chaining. |

## Details

`<command> --help` and `<command> -h` work for every command and print the same text as `help <command>`. They are checked before anything runs, so `pick --help` or `highlight --help` print help instead of starting the command, and a chain containing `--help` runs nothing. Help goes to stdout and exits 0. An unknown `<command>` prints `Unknown command 'lst'. Did you mean 'list'?` (the suggestion appears only for near misses) and a pointer to `window-tool help` to stderr, without the usage screen, and exits 1.

Each command's usage line shows how it uses `--app`: `--app <name-or-id>` when it is required, `[--app <name-or-id>]` when it is optional (`id=` selectors find the app themselves), and nothing when the command ignores it.

## Examples

```sh
window-tool help
window-tool help snap
window-tool snap --help
window-tool --app Safari focus 0 + highlight -h   # prints highlight's help, runs nothing
```
