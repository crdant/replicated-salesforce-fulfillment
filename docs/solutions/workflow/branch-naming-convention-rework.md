---
title: Branch naming convention not followed during parallel worktree development
category: workflow
date: 2026-03-16
severity: medium
tags: [branch-naming, conventions, worktrees, parallel-development, documentation]
components: [git, workflow, documentation]
root_cause: Branch naming convention was not documented in CLAUDE.md, leading to branches missing the {author} segment
---

# Branch Naming Convention Not Followed During Parallel Worktree Development

## Problem

Three branches were created without following the project's naming convention:

| Created | Should have been |
|---------|-----------------|
| `feature/7-salesforce-data-model` | `feature/claude/defines-salesforce-data-model` |
| `feature/8-enterprise-portal-fulfillment` | `feature/claude/refactors-fulfillment-to-portal` |
| `feature/9-sync-guard-site-docs` | `feature/claude/adds-sync-guard` |

The convention is `{type}/{author}/{verb-phrase}` but the branches omitted
the author segment entirely. This required closing 3 PRs, renaming all
branches, deleting old remote branches, pushing new ones, and recreating 3 PRs.

## Root Cause

The convention existed only implicitly in the repo's branch history (e.g.,
`feature/crdant/creates-trial-license`, `chore/claude/prepares-for-worktrees`).
Without a CLAUDE.md documenting it, the pattern was missed during parallel
worktree setup.

## Solution

Documented the convention in CLAUDE.md:

```markdown
### Branch Naming

`{type}/{author}/{verb-phrase-description}`

- Types: `feature`, `chore`, `docs`, `fix`
- Author: `crdant` (Chuck), `claude` (Claude)
- Examples: `feature/claude/adds-sync-guard`, `chore/claude/prepares-claude-md`
```

The rename process for each branch:
```bash
git branch -m feature/7-salesforce-data-model feature/claude/defines-salesforce-data-model
git push origin :feature/7-salesforce-data-model
git push -u origin feature/claude/defines-salesforce-data-model
```

## Prevention

- Always read CLAUDE.md before creating branches
- The convention is now documented — this shouldn't recur
- When in doubt, check existing branches: `git branch -a | head -10`

## Related

- PR #19: "Adds project conventions file" — where the CLAUDE.md was created
- `docs/solutions/integration-issues/gh-cli-wrong-remote-resolution.md` — related rework in same session
