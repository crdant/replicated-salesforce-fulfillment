---
title: GitHub CLI silently resolves to wrong repository with multiple git remotes
category: workflow
date: 2026-03-16
severity: medium
tags: [git-remotes, github-cli, remote-resolution, worktrees, pr-creation]
components: [git, github-cli, worktrees, remotes]
root_cause: gh CLI defaults to upstream remote over origin when multiple remotes exist, causing branch lookup failures on the wrong repository
---

# GitHub CLI Silently Resolves to Wrong Repository with Multiple Git Remotes

## Problem

`gh pr create` fails with a misleading error when a git repo has two remotes
pointing to different GitHub repositories:

```
pull request create failed: GraphQL: Head sha can't be blank, Base sha can't
be blank, No commits between main and feature/7-salesforce-data-model, Head
ref must be a branch (createPullRequest)
```

The branches exist, the commits are there, and the compare API confirms
commits ahead of main. But `gh` can't find them because it's looking at the
wrong repo.

## Investigation

1. Verified branches existed on remote:
   ```bash
   gh api repos/crdant/cold-leads-to-hot-signal/branches --jq '.[].name'
   # All three branches present
   ```

2. Verified commits ahead:
   ```bash
   gh api repos/crdant/cold-leads-to-hot-signal/compare/main...feature/7-salesforce-data-model --jq '.total_commits'
   # Returns: 1
   ```

3. Tried running from worktree directory — same error.

4. Tried running from main repo directory — same error.

5. Checked what `gh` thinks the repo is:
   ```bash
   gh repo view --json nameWithOwner
   # Returns: crdant/replicated-salesforce-fulfillment (wrong!)
   ```

6. Checked remotes:
   ```bash
   git remote -v
   # origin    git@github.com:crdant/cold-leads-to-hot-signal.git
   # upstream  https://github.com/crdant/replicated-salesforce-fulfillment.git
   ```

## Root Cause

The `gh` CLI uses a precedence algorithm to determine which repository to
operate on. When multiple remotes exist, it prefers `upstream` over `origin`.
Branches were pushed to `origin` (cold-leads-to-hot-signal), but `gh` resolved
to `upstream` (replicated-salesforce-fulfillment) where those branches don't
exist.

The `gh` remote resolution order:

1. Explicit `--repo` flag (highest priority)
2. `GH_REPO` environment variable
3. `upstream` remote
4. `origin` remote (lowest priority in multi-remote setups)

## Solution

### Immediate workaround

Use `--repo` explicitly:

```bash
gh pr create --repo crdant/cold-leads-to-hot-signal \
  --head feature/7-salesforce-data-model \
  --base main \
  --title "Your PR Title" \
  --body "Description"
```

### Permanent fix

Consolidate to a single remote pointing to the canonical repo:

```bash
git remote set-url origin https://github.com/crdant/replicated-salesforce-fulfillment.git
git remote remove upstream
```

Verify:

```bash
git remote -v
# origin  https://github.com/crdant/replicated-salesforce-fulfillment.git (fetch)
# origin  https://github.com/crdant/replicated-salesforce-fulfillment.git (push)

gh repo view --json nameWithOwner --jq '.nameWithOwner'
# crdant/replicated-salesforce-fulfillment
```

## Prevention

### Keep a single `origin` remote

The simplest prevention is to avoid multi-remote setups. If the canonical repo
changes, update `origin` rather than adding a second remote.

### Diagnostic one-liner

When `gh pr create` fails unexpectedly:

```bash
git remote -v && echo "---" && gh repo view --json nameWithOwner && echo "---" && git branch -vv
```

This shows all three signals at once: where remotes point, what `gh` thinks
the repo is, and where branches are tracking.

### Avoid naming remotes `upstream`

The name `upstream` has special meaning to `gh`. If you need a second remote,
use a descriptive name like `fork` or `secondary` instead.

## Related

- Commit `38ff2bf`: "Prepares repository for parallel worktree development (#14)"
- No existing `docs/solutions/` entries for this topic prior to this document
