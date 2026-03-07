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

## Pre-commit Swift review

Before every commit that includes changes to Swift code (`src/*.swift`), launch a background Agent to review the changes:

1. **Agent role:** Principal Swift Engineer reviewing for idiomatic Swift, clean code, good software design, and coding best practices.
2. **What to review:** Run `git diff --cached -- src/` (or `git diff -- src/` for unstaged changes about to be committed) and review all Swift changes.
3. **If the agent has suggestions:** Launch a second agent (Swift Refactoring Expert) to apply the suggestions to the code. Then re-build with `./build.sh` to verify compilation.
4. **Commit strategy:**
   - If the refactoring changes are **minor** (naming, style, small cleanups): amend them into the same commit.
   - If the refactoring changes are **major** (structural changes, new abstractions, significant redesign): make a separate follow-up commit.
5. **If no suggestions:** Proceed with the commit as-is.

This review is mandatory for all Swift code changes. Do not skip it.
