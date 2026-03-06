# window-tool

A macOS CLI for fast window management using the Accessibility API (`AXUIElement`). Written in Swift.

See [README.md](../README.md) for full usage, commands, and examples.

## Project structure

- `src/window-tool.swift` — Single-file Swift source
- `build.sh` — Compiles the binary to `bin/window-tool`
- `release.sh` — Tags and pushes semver releases

## Development workflow

1. Edit `src/window-tool.swift`
2. Run `./build.sh` to compile
3. Test with `./bin/window-tool <command>`

## Releasing

Use `./release.sh` for version tagging. See README for details.
