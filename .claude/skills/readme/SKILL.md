---
name: readme
description: Create and update command documentation in docs/ and the README.md commands table
argument-hint: [create|update] [command-name]
---

# README Skill

Create and update command documentation for window-tool.

## Usage

```
/readme create [command-name]
/readme update [command-name]
```

If `command-name` is omitted, operates on all commands.

## Commands

### create

Creates missing documentation:

1. **docs/README.\<command\>.md** — For each command missing a README, create one using the template below
2. **README.md commands table** — Add any new commands to the table

### update

Updates existing documentation:

1. **Check for changes** — Compare current CLI code against existing docs
2. **Update docs** — Re-analyze the command and update its README
3. **Update README.md** — Sync the commands table (add/remove/update entries)

## Command Discovery

Commands are defined in `src/window-tool.swift`:

1. Read the `switch command` block in the `// MARK: - Main` section to find all commands
2. Read the corresponding command function (e.g., `moveCommand`, `snapCommand`) for behavior details
3. Read the `usage()` function for the help text description of each command
4. Check argument parsing in each switch case for required/optional args and flags

## Command README Template (docs/README.\<command\>.md)

```markdown
# window-tool <command>

<1-2 sentence description of what the command does>

## Usage

\`\`\`sh
window-tool [--app <bundle-id>] <command> [args...]
\`\`\`

## Arguments

<If the command has positional arguments, list them in a table:>

| Argument | Required | Description |
|----------|----------|-------------|
| `<arg>` | Yes/No | What it does |

<If no arguments beyond the command name, omit this section>

## Options

<If the command has flags like --gap, list them:>

| Option | Description |
|--------|-------------|
| `--flag <value>` | What it does |

<If no command-specific options, omit this section>

## Details

<Explain behavior, what it does, edge cases, important notes>

## Examples

\`\`\`sh
<Practical usage examples>
\`\`\`
```

## README.md Commands Table

The commands table in `README.md` should look like:

```markdown
### Commands

| Command | Docs | Description |
|---------|------|-------------|
| name | [README](docs/README.name.md) | Short description |
```

Commands with `-by-title` variants should be documented together in a single doc file (e.g., `move` and `move-by-title` share `docs/README.move.md`).

## Instructions for Claude

### When running `create`:

1. **Find all commands** from the `switch command` block in `src/window-tool.swift`
2. **Group `-by-title` variants** with their base command (they share one doc file)
3. **Check which are missing** `docs/README.<command>.md`
4. **For each missing command:**
   - Read the command function for behavior details
   - Read the switch case for argument parsing (required args, optional args, flags)
   - Read the `usage()` text for the short description
   - Create `docs/README.<command>.md` using the template
5. **Update the README.md commands table** with any new entries

### When running `update`:

1. **For each command to update:**
   - Read the current `docs/README.<command>.md`
   - Read the current command function and switch case
   - Compare and update the README if anything changed (new args, changed behavior, etc.)
2. **Sync the README.md commands table:**
   - Add entries for new commands
   - Remove entries for deleted commands
   - Update descriptions if they changed
3. **If a specific command was requested**, only process that one

### Important notes:

- Use `docs/` directory for command READMEs
- Filenames use the base command name (e.g., `README.move.md` covers both `move` and `move-by-title`)
- Keep descriptions concise
- Omit optional sections (Arguments, Options, Details) if not applicable
- Global options (`--app`, `--json`, `--version`) are documented in the main README, not in individual command docs
