---
title: Nested worktrees created by agent dispatch from existing worktree
category: workflow
date: 2026-03-16
severity: high
tags: [agents, worktrees, git, branch-naming, parallel-development, dispatch]
components: [git-worktrees, claude-code-agents, branch-management]
root_cause: Agent inherited CWD from within existing worktree; git worktree add created nested structure instead of sibling worktree from repo root
---

# Nested Worktrees Created by Agent Dispatch from Existing Worktree

## Problem

When dispatching parallel Claude Code agents to work in git worktrees, the
agents created nested worktrees inside an existing worktree instead of using
the sibling worktrees pre-created by the orchestrator.

Expected structure:
```
.worktrees/
  baselines-research/          ← sibling
  prepares-claude-md/          ← sibling
  8-enterprise-portal-fulfillment/
```

Actual structure:
```
.worktrees/
  8-enterprise-portal-fulfillment/
    .worktrees/
      baselines-research/      ← nested inside #8
      prepares-claude-md/      ← nested inside #8
```

The agent also committed to a branch named `chore/baselines-research` instead
of the pre-created `docs/claude/baselines-research`. The push succeeded but
the PR failed with "No commits between main and docs/claude/baselines-research"
because the intended branch had no new commits.

## Root Cause

The agent's shell inherited a working directory inside an existing worktree
(`8-enterprise-portal-fulfillment`). When the agent ran `git worktree add`,
git resolved the path relative to that CWD rather than the repo root, creating
a nested structure. The agent also created its own branch instead of using the
one pre-created by the orchestrator.

## Detection

```bash
# Quick check for nested worktrees
git worktree list | grep ".worktrees.*/.worktrees"

# Or find nested .worktrees directories
find .worktrees -type d -name ".worktrees"
```

## Solution

**Agents should never create their own worktrees.** The orchestrator must:

1. Pre-create all worktrees from the repo root before dispatching agents:
   ```bash
   cd /repo  # repo root, NOT inside a worktree
   git worktree add -b docs/claude/baselines-research .worktrees/baselines-research main
   ```

2. Pass the exact worktree path to the agent as its working directory

3. Instruct agents to work in the provided directory — no `git worktree add`

4. Verify after completion:
   ```bash
   git worktree list  # no nested paths
   git log --oneline docs/claude/baselines-research  # commit is on the right branch
   ```

## Prevention

- Orchestrator creates worktrees; agents consume them
- Always create worktrees from the repo root, never from inside another worktree
- Verify branch names match after agent completion
- Agent prompts should explicitly say "do NOT create worktrees"

## Related

- `docs/solutions/integration-issues/gh-cli-wrong-remote-resolution.md`
- Commit `38ff2bf`: "Prepares repository for parallel worktree development (#14)"
