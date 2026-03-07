---
name: release
description: Release window-tool by analyzing changes, bumping the version tag, and pushing
argument-hint: [patch|minor|major|<version>]
---

# Release window-tool

Analyze changes since the last release, suggest a version bump, and release using `./release.sh`.

## Usage

```
/release
/release patch
/release minor
/release major
/release <version>
```

## Instructions

When the user invokes this skill:

### Prerequisites

1. **Verify on main branch** - if not, inform the user and stop
2. **Verify no uncommitted changes** to tracked files - untracked files are fine
3. **Build first** - run `./build.sh` to ensure the binary compiles cleanly before releasing

### If an argument is provided (patch, minor, major, or explicit version):

Skip change analysis and pass the argument directly to `./release.sh`:

1. Run `./release.sh <argument>`
2. Report the result to the user

### If NO argument is provided:

1. **Get the current version** by running `./release.sh` (with no args, it prints the current version)
2. **Find the last tag** for this project (e.g., `v0.1.0`)
3. **Analyze changes since last tag**:
   - Run `git log <last-tag>..HEAD --oneline` to see commits
   - Run `git diff <last-tag>..HEAD -- src/` to see what changed in the source
   - If no previous tag exists, this is the initial release
4. **Suggest version bump** based on changes:
   - **Patch** (x.y.Z): Internal changes only - refactoring, bug fixes, documentation, code cleanup
   - **Minor** (x.Y.0): New features added - new commands, new flags, new functionality
   - **Major** (X.0.0): Breaking changes - removed commands, changed default behavior, renamed flags, modified output format
5. **Show analysis to user**:
   - Display the current version
   - Summarize the changes since last tag
   - Show your recommended bump type with reasoning
   - Let the user confirm or choose a different version
6. Once confirmed, run `./release.sh <bump-type-or-version>` to tag and push

## Example

```
/release
```

This will:
- Run `./release.sh` to get the current version (e.g., "Current version: v0.1.0")
- Run `git log v0.1.0..HEAD --oneline` to see commits since that tag
- Run `git diff v0.1.0..HEAD -- src/` to analyze source changes
- Suggest a version bump:
  - "I see 9 commits with refactoring changes: enum extraction, error handling improvements, and bug fixes. No new commands or breaking changes. I recommend a **patch** bump to v0.1.1."
  - Or: "I see new commands were added (snap, watch, stack). These are new features, so I recommend a **minor** bump to v0.2.0."
  - Or: "I see the default bundle ID was changed and output format was modified. These break backward compatibility, so I recommend a **major** bump to v1.0.0."
- Let the user confirm or choose differently
- Run `./release.sh patch` (or minor/major/explicit version as chosen)

### With explicit bump type

```
/release minor
```

This will skip analysis and run `./release.sh minor` directly.

## Change Analysis Guidelines

When analyzing the diff, look for these patterns:

### Patch (bug fixes, internal changes)
- Fixed typos or documentation
- Refactored code without changing behavior
- Fixed bugs that made the tool not work as documented
- Performance improvements
- Code cleanup

### Minor (new features, backward compatible)
- New commands added
- New command-line flags or options
- New output formats (when existing formats still work)
- New functionality that doesn't affect existing behavior

### Major (breaking changes)
- Removed commands or flags
- Changed default behavior (e.g., default `--app` bundle ID)
- Renamed commands or flags
- Changed output format in a way that breaks scripts
- Changed exit codes
- Removed features

## Error Handling

- If `./release.sh` fails, report the error to the user
- If the tag already exists, `./release.sh` will report it
- If the build fails, do not proceed with the release
- If not on main or working tree is dirty, `./release.sh` will catch this too, but check early to avoid a wasted build
