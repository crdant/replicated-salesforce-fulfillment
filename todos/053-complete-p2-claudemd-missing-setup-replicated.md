---
status: complete
priority: p2
issue_id: "053"
tags:
  - code-review
  - agent-accessibility
  - documentation
dependencies: []
---

# CLAUDE.md not updated with make setup-replicated

## Problem Statement

The `CLAUDE.md` file lists Makefile targets under "Common Commands" but does not include `make setup-replicated`. Since CLAUDE.md serves as the agent's primary context, an agent asked to "set up the Replicated integration" would not discover this orchestrator target and would attempt to run individual sub-targets manually, potentially in the wrong order.

This matches a prior documented pattern: todo #043 (`claudemd-missing-webhook-subscription`) was the same class of issue — new Makefile targets not added to CLAUDE.md.

## Findings

**File:** `CLAUDE.md` lines 17-21 — Common Commands section

**Flagged by:** agent-native-reviewer (Warning)

**Evidence:**
- `CLAUDE.md` lists `make deploy`, `make retrieve`, `make credentials`, `make channels`, `make webhook-subscription`, `make import`, `make clean`
- `make setup-replicated` is absent
- Prior todo #043 was the exact same class of issue

## Proposed Solutions

### Option A: Add setup-replicated to Common Commands
```markdown
make setup-replicated  # Configure all Replicated Platform resources (channels, portal, entitlements, webhooks)
```
- **Pros:** Agent discoverability, consistent with prior fix pattern
- **Cons:** None
- **Effort:** Small (1 line)
- **Risk:** Low

## Recommended Action

Option A.

## Technical Details

**Affected files:**
- `CLAUDE.md`

## Acceptance Criteria

- [ ] `make setup-replicated` appears in CLAUDE.md Common Commands
- [ ] An agent reading only CLAUDE.md can discover the orchestrator target

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #70 code review | Recurring pattern — new targets must be added to CLAUDE.md |

## Resources

- PR #70: https://github.com/crdant/replicated-salesforce-fulfillment/pull/70
- Prior: todo #043 (same class of issue)
