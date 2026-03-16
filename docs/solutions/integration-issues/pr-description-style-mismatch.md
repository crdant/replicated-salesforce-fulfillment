---
title: PR description style mismatch between agent output and project convention
category: integration-issues
date: 2026-03-16
severity: medium
tags: [pr-writing, agent-expectations, documentation, conventions]
components: [pull-requests, pull-request-author-agent, documentation]
root_cause: Pull-request-author agent uses a default Summary + Test plan template that doesn't match the project's TL;DR + Details conversational style
---

# PR Description Style Mismatch Between Agent Output and Project Convention

## Problem

The pull-request-author agent generated PR descriptions in a `## Summary` +
`## Test plan` format with bullet checklists. The project uses a `TL;DR` +
`Details` format with conversational, story-driven prose.

Agent output:
```
## Summary
- Adds SyncGuard to prevent infinite loops
- Updates documentation

## Test plan
- [ ] Verify no infinite loops occur
- [ ] Check documentation is accurate
```

Project convention (from PRs #1-5):
```
TL;DR
-----

Adds SyncGuard to prevent infinite loops in bidirectional sync

Details
-------

The Account trigger was firing recursively when processing inbound
webhooks. To solve this, I introduced SyncGuard — a static set that
tracks IDs currently being processed and short-circuits the trigger
if it detects a record already in flight...
```

## Root Cause

The project's PR style was only visible by reading the 5 existing merged PRs.
It wasn't documented anywhere. The pull-request-author agent has its own
default template that doesn't match.

## Discovery

User asked: "Does that follow the format that the pull request author agent
uses?" This prompted reading all 5 PRs to extract the actual style.

## The Project Style

Key characteristics extracted from PRs #1-5 (all by @crdant):

- **TL;DR**: One sentence, uses `-----` underline (not `##`)
- **Details**: First-person, narrative prose — explains the *why*, not a list of *what*
- **Conversational tone**: "I realized that wasn't quite right", "My best guess is..."
- **No test plan section**
- **No emoji or "Generated with Claude Code" footer**

## Solution

Before writing PR descriptions:

1. Read 2-3 recent merged PRs to extract the project voice
2. Use the pull-request-author agent as a starting point, then rewrite to match
3. Convert bullet lists to narrative prose
4. Replace `## Summary` with `TL;DR` / `-----`
5. Replace `## Test plan` with `Details` / `-------` and explain the reasoning

## Prevention

Add PR style guidance to CLAUDE.md. Or just read recent PRs before writing
new ones — the style is consistent enough to pick up from examples.

## Related

- PRs #1-5 on `crdant/replicated-salesforce-fulfillment` — the style reference
- `docs/solutions/integration-issues/branch-naming-convention-rework.md` — same theme of undocumented conventions
