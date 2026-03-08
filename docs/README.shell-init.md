# window-tool shell-init

Print a shell integration snippet that sets the WINDOWID environment variable.

## Usage

```sh
window-tool shell-init <shell>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<shell>` | Yes | Shell type: `zsh`, `bash`, or `fish` |

## Details

Outputs a snippet you can add to your shell config file. The snippet sets `WINDOWID` to the CGWindowID of the active terminal window at shell startup, making it available for later use with `id=<N>` selectors.

## Examples

```sh
window-tool shell-init zsh
window-tool shell-init bash
window-tool shell-init fish

# Add to ~/.zshrc:
eval "$(window-tool shell-init zsh)"
```
