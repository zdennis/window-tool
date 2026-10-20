# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS CLI for fast window management using the Accessibility API (`AXUIElement`). Written as a single-file Swift program. Designed for both human and machine (AI agent, scripting) use.

See [README.md](../README.md) for full usage, commands, and examples.

## Project structure

- `src/window-tool.swift` — Single-file Swift source
- `bin/window-tool` — Compiled binary (gitignored)
- `build.sh` — Compiles with `swiftc -O` linking Cocoa and ScreenCaptureKit frameworks
- `release.sh` — Tags and pushes semver releases
- `docs/README.<command>.md` — Per-command documentation
- `script/` — Dev tooling (feature requests management)
- `.claude/agents/` — Review agent definitions
- `.claude/skills/` — Claude Code skills (`/release`, `/readme`)

## Development workflow

1. Edit `src/window-tool.swift`
2. Run `./build.sh` to compile
3. Test with `./bin/window-tool <command>`

## Source architecture

The source is organized into `// MARK:` sections in this order (`grep -n 'MARK' src/window-tool.swift` lists them):

1. **Configuration** — `Config` struct (bundleId, flags, chaining state), `printJSON`/`flushJSONBuffer`
2. **Errors** — `WindowToolError` enum with `LocalizedError` conformance
3. **Argument Parsing Helpers** — `parseInt`, `parseDouble`, flag parsers for each command's options
4. **Color Parsing** — `parseColor`, flag parsers for highlight/border/flash/dim
5. **Undo History** — `Codable` window frames for `undo`, saved under `NSTemporaryDirectory()`
6. **Accessibility Helpers** — `resolveAppIdentifier` (fuzzy app matching), `getAppElement`, `getCGWindowID` (private API via `@_silgen_name`), `WindowInfo` struct, `getWindows`, `moveWindow`, `resizeWindow`
7. **Window Resolution** — `WindowSelector` enum (`.byIndex`, `.byTitle`, `.byWindowID`), `parseWindowSelector`, `resolveSelectorAndArgs` (inherits `Config.lastSelector` when chaining), `resolveWindow`, `findWindowByID` (cross-app CGWindowList lookup)
8. **Screen Helpers** — `screensCommand`, `activeScreenCommand`, `activeWindowCommand`, `shellInitCommand`, coordinate conversion helpers
9. **Accessibility Check** — `checkAccessibility` via `AXIsProcessTrusted()`
10. **Commands** — Core window operations (list, info, move, resize, snap, focus, etc.)
11. **Highlight Overlay**, **Overlay PID Files**, **Dim Overlay**, **Border Overlay** — `NSWindow` overlays run under `NSApplication.run()`; PID files let a later call remove a running dim/border
12. **Element Paths**, **Text Command**, **Press Command** — Accessibility element tree addressing (`0.2.1` paths) and the commands that read or press elements
13. **Wait Command** — Polls until a window appears, disappears, or stabilizes
14. **Preview Command**, **Record Command**, **Pip Command** — Screenshot via ScreenCaptureKit, video recording with AVAssetWriter, picture-in-picture
15. **Identify Command**, **Pick Command** — Visual window identification overlays, click-to-select
16. **Layout Types** — save-layout/restore-layout (stored in `~/.config/window-tool/layouts`), plus stack, watch, columnize
17. **Command Metadata** — `CommandSpec` table that drives `help` and `commands --json`; every new command needs an entry
18. **Main** — Argument parsing, command chaining (`+` separator), `runCommand` dispatch switch

### Key patterns

- **Window selectors**: Commands accept `<index>`, `id=<CGWindowID>`, or `title=<pattern>`. The `id=` form auto-detects the owning app, making `--app` optional.
- **Command chaining**: `+` separates commands sharing `--app` and `--json`. Selectors inherit from the previous command when omitted.
- **App resolution**: `--app` accepts full bundle IDs or fuzzy name substrings. Exact bundle ID match first, then case-insensitive substring match. Ambiguous matches produce an error listing candidates.
- **Output**: All query commands support `--json` for structured output and tab-separated text with column headers for human output.
- **Overlays** (highlight, dim, border, identify): These run an `NSApplication` event loop. Border/dim persist until explicitly removed; highlight auto-dismisses.
- **Error handling**: Commands `throw WindowToolError`; top-level `do/catch` prints to stderr and exits 1.

## Feature requests

Feature requests live in `.worktrees/feature-requests/FEATURE_REQUESTS.md` on the orphan `feature-requests` branch.

- **Read/edit directly** via the worktree path: `.worktrees/feature-requests/FEATURE_REQUESTS.md`
- **Commit changes** with: `git -C .worktrees/feature-requests add -A && git -C .worktrees/feature-requests commit -m "message" && git -C .worktrees/feature-requests push`
- **Quick view/manage** via: `script/feature-requests` (list, create, update, complete, help)
- **Never** create feature request files on main or feature branches

## Conventions

- `bin/` is for project executables (the compiled `window-tool` binary)
- `script/` is for dev tooling (feature requests management, etc.)
- `VERSION` constant in source is bumped by `release.sh`

## Releasing

Use `./release.sh` for version tagging. See README for details.

## Pre-commit review

Before every commit, launch two review agents in parallel as background tasks, plus up to three specialists when the change calls for them. Each agent reviews **only the changes being committed** (use `git diff --cached` for staged changes, or the topic branch diff for branch-scoped review).

### Default agents (always)

1. **Supportive reviewer** — Assumes the change is worth making and checks that it delivers: does it do what it set out to, are docs and help in step, what small improvements would make it land better.
2. **Skeptical reviewer** — Looks for reasons not to ship: bugs, edge cases, regressions, behavior changes that break existing users or scripts, and complexity the change doesn't need.

### Specialists (0–3, only when the change needs that perspective)

Launch each as a background Agent, passing it the diff and the contents of its agent definition file. Pick by what the change touches; most small changes need none.

- **Workflow Automator** (`.claude/agents/workflow-automator.md`) — Changes to chaining, exit codes, or anything scripts compose with.
- **AI Agent** (`.claude/agents/ai-agent.md`) — Changes to `--json` output, `commands --json`, error codes, or discoverability.
- **Minimalist Architect** (`.claude/agents/minimalist-architect.md`) — Non-trivial code: new abstractions, shared helpers, refactors.
- **First-Day Contributor** (`.claude/agents/first-day-contributor.md`) — New patterns or conventions others will copy.
- **CLI UX Critic** (`.claude/agents/cli-ux-critic.md`) — New or renamed commands and flags, help text, error messages.

### Instructions for agents

- Each specialist should read its definition file; every agent then reviews the diff.
- Each agent should also read any files touched by the diff for full context.
- Each agent should return: a short summary, a list of issues found (if any), and a severity for each issue (minor, major, critical).
- If an agent finds **no issues**, it should say so briefly.

### After all agents complete

1. Collect all agent results.
2. If there are **no major or critical issues**: proceed with the commit.
3. If there are **major or critical issues**:
   - If the issues are fixable (code changes), fix them and include the fixes in the commit. Re-build with `./build.sh` to verify.
   - If the issues are architectural or design concerns that need discussion, write a report summarizing the findings and present it to the user before committing. Let the user decide how to proceed.
4. Minor issues can be noted in the commit or addressed in a follow-up.

This review is mandatory for all commits. Do not skip it.
