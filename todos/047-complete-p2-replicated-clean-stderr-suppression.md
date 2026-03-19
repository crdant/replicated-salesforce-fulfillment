---
status: complete
priority: p2
issue_id: "047"
tags:
  - code-review
  - error-handling
  - observability
dependencies:
  - "045"
---

# replicated-clean suppresses stderr with 2>/dev/null masking real API failures

## Problem Statement

The `replicated-clean` target uses `2>/dev/null` on the `replicated api get` call, which suppresses all stderr. If the API call fails (expired auth, network error, wrong endpoint), the error is silently discarded, `jq` receives empty input, the `while read` loop doesn't execute, and the target exits successfully. The user sees "Removing webhook subscription..." with no indication whether anything was actually removed or the API call failed entirely.

## Findings

**File:** `Makefile:41` — `replicated api get /v3/notification_subscriptions 2>/dev/null`

**Multiple agents flagged this:**
- Security sentinel: Low severity — "developer might believe cleanup succeeded when it failed silently"
- Simplicity reviewer: "drop `2>/dev/null` and let errors surface naturally"
- Learnings researcher: **Direct match with documented anti-pattern** in `docs/solutions/build-errors/makefile-error-suppression-masking-api-failures.md` and completed todo 040

**Known Pattern:** Todo 040 (`stderr-suppression-masks-real-errors`) addressed the identical issue for the `entitlements` target. The institutional learning explicitly states: "Never use blanket `2>/dev/null`."

## Proposed Solutions

### Option A: Remove `2>/dev/null` entirely
- Let stderr flow through naturally.
- **Effort**: Small (delete 12 characters)
- **Risk**: Low
- **Pros**: Simplest fix, real errors surface immediately
- **Cons**: None if extracted to a script (where `set -euo pipefail` handles failures properly)

### Option B: Capture and inspect (if keeping inline)
- Redirect stderr to a variable, check exit code, surface real errors.
- **Effort**: Medium
- **Risk**: Low
- **Pros**: Clean output
- **Cons**: Complex inline logic

## Recommended Action

Option A — remove `2>/dev/null`. If combined with extraction to a script (todo 046), `set -euo pipefail` handles failures properly.

## Technical Details

**Affected files:**
- `Makefile` — Line 41

## Acceptance Criteria

- [ ] API auth failure produces visible error output and non-zero exit
- [ ] Network error produces visible error output and non-zero exit
- [ ] Successful cleanup with no matching subscriptions prints informative message

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #69 code review | Third time this anti-pattern found; see todos 040, 041 |

## Resources

- PR #69: https://github.com/crdant/replicated-salesforce-fulfillment/pull/69
- Past learning: docs/solutions/build-errors/makefile-error-suppression-masking-api-failures.md
- Precedent: Todo 040 (stderr suppression in entitlements)
