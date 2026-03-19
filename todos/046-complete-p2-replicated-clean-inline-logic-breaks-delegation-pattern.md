---
status: complete
priority: p2
issue_id: "046"
tags:
  - code-review
  - architecture
  - pattern-consistency
dependencies:
  - "045"
---

# replicated-clean inlines multi-step logic instead of delegating to hack/ script

## Problem Statement

Every other Makefile target delegates to a script in `hack/`. The `replicated-clean` target is the only one that embeds a multi-line shell pipeline (API call, jq filter, while loop) directly in the Makefile. This breaks the established delegation pattern and makes the logic harder to test, debug, and maintain. It also duplicates the subscription name `"Salesforce CRM Sync"` that already exists in `hack/setup-webhook-subscription` line 10.

## Findings

**File:** `Makefile:39-43` — 4-line inline pipeline

**All three configured review agents flagged this independently:**
- Architecture strategist: "only target in the entire Makefile that contains inline business logic"
- Simplicity reviewer: "consistency/DRY violation — extraction wins given the existing convention"
- Learnings researcher: Confirmed match with documented pattern — todo 041 (complete) addressed the same issue for the `entitlements` target

**Known Pattern:** Todo 041 (`inline-entitlements-inconsistent-with-hack-pattern`) was the same finding for `entitlements` — inline Makefile logic was extracted to `hack/create-license-field`.

## Proposed Solutions

### Option A: Extract to `hack/clean-webhook-subscription`
- Create a script following the established pattern: `set -euo pipefail`, env var validation, proper error handling, shared subscription name.
- Makefile target becomes a one-liner: `hack/clean-webhook-subscription`
- **Effort**: Small
- **Risk**: Low
- **Pros**: Follows convention, fixes DRY violation, enables proper error handling, resolves 045 simultaneously
- **Cons**: Adds one file to `hack/`

### Option B: Keep inline but add comments
- Document the inline logic with a comment explaining why it's not in a script.
- **Effort**: Small
- **Risk**: Low
- **Pros**: No new files
- **Cons**: Still breaks pattern, still duplicates subscription name, still lacks `set -euo pipefail`

## Recommended Action

Option A — extract to `hack/clean-webhook-subscription`. Follows the precedent set by todo 041 (entitlements extraction).

## Technical Details

**Affected files:**
- `Makefile` — Lines 39-43
- New: `hack/clean-webhook-subscription`
- Related: `hack/setup-webhook-subscription` (line 10, subscription name constant)

## Acceptance Criteria

- [ ] `replicated-clean` target delegates to a `hack/` script
- [ ] Script uses `set -euo pipefail`
- [ ] Subscription name is not duplicated across files (or is co-located in `hack/`)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #69 code review | Same pattern as completed todo 041 |

## Resources

- PR #69: https://github.com/crdant/replicated-salesforce-fulfillment/pull/69
- Precedent: Todo 041 (entitlements extraction)
- Past learning: docs/solutions/build-errors/makefile-error-suppression-masking-api-failures.md
