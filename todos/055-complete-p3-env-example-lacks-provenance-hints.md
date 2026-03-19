---
status: complete
priority: p3
issue_id: "055"
tags:
  - code-review
  - documentation
  - agent-accessibility
dependencies: []
---

# .env.example placeholder values lack provenance hints

## Problem Statement

The `.env.example` file uses placeholder values like `your-app-slug` and `your-webhook-secret-here` without indicating where to obtain the real values or what format they should be in. An agent or new contributor cannot determine the correct values from the file alone.

## Findings

**File:** `.env.example` lines 5, 9-10

**Flagged by:** agent-native-reviewer (Warning)

## Proposed Solutions

### Option A: Add inline comments with provenance
```
# Replicated app slug (from `replicated app ls` or Vendor Portal > Settings)
REPLICATED_APP=your-app-slug

# HMAC signing secret for webhook verification (generate with `openssl rand -hex 32`)
REPLICATED_WEBHOOK_SECRET=your-webhook-secret-here
```
- **Pros:** Self-documenting, agent-friendly
- **Cons:** More verbose
- **Effort:** Small
- **Risk:** Low

## Technical Details

**Affected files:**
- `.env.example`

## Acceptance Criteria

- [ ] Each placeholder value has a comment explaining where to obtain it

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #70 code review | Agent discoverability improvement |

## Resources

- PR #70: https://github.com/crdant/replicated-salesforce-fulfillment/pull/70
