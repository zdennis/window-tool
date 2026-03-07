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

## Pre-commit review

Before every commit, launch the following 5 agents in parallel as background tasks. Each agent reviews **only the changes being committed** (use `git diff --cached` for staged changes, or the topic branch diff for branch-scoped review).

### Agents

Launch each as a background Agent, passing it the diff and the contents of its agent definition file:

1. **Workflow Automator** (`.claude/agents/workflow-automator.md`) — Evaluates whether changes support composable, scriptable automation workflows.
2. **AI Agent** (`.claude/agents/ai-agent.md`) — Evaluates discoverability, consistency, and machine-parseable behavior.
3. **Minimalist Architect** (`.claude/agents/minimalist-architect.md`) — Reviews code quality, complexity, idiomatic Swift, and architecture.
4. **First-Day Contributor** (`.claude/agents/first-day-contributor.md`) — Evaluates whether patterns are obvious and the codebase is easy to ramp up on.
5. **CLI UX Critic** (`.claude/agents/cli-ux-critic.md`) — Reviews the external interface: naming, help text, error messages, and consistency.

### Instructions for agents

- Each agent should read its definition file, then review the diff.
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
