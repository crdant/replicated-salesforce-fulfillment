---
title: Worktree location convention mismatch between Claude Code and project
category: integration-issues
date: 2026-03-16
severity: medium
tags: [git-worktrees, claude-code, parallel-development, conventions]
components: [git-worktrees, claude-code-agents]
root_cause: Claude Code's default worktree path (.claude/worktrees/) differs from project convention (.worktrees/); no convention check performed before creation
---

# Worktree Location Convention Mismatch

## Problem

When creating git worktrees for parallel issue development, worktrees were
placed in `.claude/worktrees/` (Claude Code's internal default) instead of
`.worktrees/` (the project's established convention). The user had to request
the worktrees be moved to the correct location.

A secondary issue compounded this: background agents were launched with
`isolation: worktree` to implement issues when the user only wanted bare
worktrees created for their own use. The agents created branches and began
work, which then had to be cleaned up before correct worktrees could be
created.

## Root Cause

Two independent failures:

1. **Convention detection skipped.** The project already had a worktree at
   `.worktrees/compounds-learning` and `.worktrees/` in `.gitignore` (line 31),
   but no check was performed before creating new worktrees. Claude Code's
   `EnterWorktree` tool defaults to `.claude/worktrees/`, which diverges from
   the project convention.

2. **User intent misread.** "Create worktrees" was interpreted as "implement
   issues in worktrees." The `Agent` tool was called with `isolation: worktree`
   and full implementation prompts, when the user wanted only the directory
   structure and branches provisioned.

## Detection

```bash
# Check where existing worktrees live
git worktree list

# Verify .gitignore convention
grep -n worktree .gitignore
```

If `git worktree list` shows paths under `.worktrees/` but new worktrees were
created under `.claude/worktrees/`, the convention was not followed.

## Solution

### Step 1: Discover the project convention

```bash
git worktree list
```

Output reveals the established pattern:
```
/path/to/repo                              main
/path/to/repo/.worktrees/compounds-learning  docs/crdant/compounds-learning
```

Convention: `.worktrees/`, not `.claude/worktrees/`.

### Step 2: Clean up misplaced worktrees (if needed)

```bash
git worktree remove --force .claude/worktrees/issue-20
git branch -D feature/claude/adds-instance-field-level-security
```

### Step 3: Create worktrees in the correct location

```bash
git worktree add .worktrees/issue-20 -b feature/claude/adds-instance-field-level-security main
git worktree add .worktrees/issue-21 -b docs/claude/evaluates-secret-storage main
git worktree add .worktrees/issue-10 -b feature/claude/implements-webhook-receiver main
```

### Step 4: Verify

```bash
git worktree list
# All worktrees should be siblings under .worktrees/
```

## Prevention

### Convention discovery (before any worktree operation)

Always run `git worktree list` first. Match the directory pattern of existing
worktrees. If none exist, check `.gitignore` for a documented convention.

### Intent classification

| User says | Correct action |
|-----------|----------------|
| "Create worktrees" | `git worktree add` only — bare branches, no implementation |
| "Implement issue #X in a worktree" | Create worktree, then implement |
| "Work on issue #X" | Clarify whether to create worktree or use existing one |

"Create worktrees" never implies "launch agents to implement features."

### Document the convention

The `.worktrees/` convention should be in CLAUDE.md and project memory so it's
known without discovery in future sessions.

## Related

- `docs/solutions/workflow/nested-worktrees-from-agent-dispatch.md` — agents
  creating nested worktrees inside existing worktrees (related but distinct)
- `docs/solutions/workflow/branch-naming-convention-rework.md` — undocumented
  conventions leading to agent errors
- `.gitignore` line 31: `.worktrees/`
- Commit `38ff2bf`: "Prepares repository for parallel worktree development"
