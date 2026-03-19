---
status: complete
priority: p2
issue_id: "040"
tags:
  - code-review
  - error-handling
  - observability
  - agent-accessibility
dependencies: []
---

# Blanket stderr suppression masks real errors in entitlements target

## Problem Statement

The `entitlements` Makefile target uses `2>/dev/null || echo "Field member_count_max already exists"` to handle the idempotent case (field already exists). However, this suppresses ALL stderr and treats ANY non-zero exit code as "field already exists" — including authentication failures, network timeouts, malformed requests, and permission errors.

A developer with an expired API token will see "Field member_count_max already exists" and believe the field was created, when the API call never succeeded.

## Findings

**File:** `Makefile:18-22` — Blanket error suppression

**All 5 review agents flagged this finding independently:**
- Security sentinel: Medium severity — "authentication failure would be silently swallowed"
- Architecture strategist: Medium risk — "violates principle of least surprise"
- Agent-native reviewer: Critical for agents — "an agent concludes the field is present when nothing happened"
- Learnings researcher: Confirmed match with documented anti-pattern in `docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md`
- Simplicity reviewer: Acknowledged as correctness concern

**Known Pattern:** The `hack/create-channel` script (lines 40-43) demonstrates the correct pattern — it suppresses CLI stderr but provides its own diagnostic and exits non-zero on real failures.

## Proposed Solutions

### Option A: Remove `2>/dev/null` entirely
- Let stderr flow through naturally. The `|| echo` still handles 409 gracefully.
- On a real error, the user/agent sees both the stderr error AND the fallback message.
- **Effort**: Small (delete 11 characters)
- **Risk**: Low
- **Pros**: Simplest fix, immediately surfaces real errors
- **Cons**: 409 stderr message is visible alongside "already exists" echo (slightly noisy)

### Option B: Capture and inspect stderr
- Redirect stderr to a variable, check for "already exists" or 409, surface other errors.
- **Effort**: Medium
- **Risk**: Low
- **Pros**: Clean output for all paths
- **Cons**: More complex inline logic; may warrant extracting to a hack/ script

### Option C: Extract to hack/create-license-field script
- Move logic to a dedicated script with `set -euo pipefail` and proper error differentiation.
- **Effort**: Medium
- **Risk**: Low
- **Pros**: Follows project convention (see completed todo 016), proper error handling
- **Cons**: Adds a file for what is currently 4 lines of logic

## Recommended Action

Option C — extract to `hack/create-license-field` with proper error differentiation. Resolves both this todo and 019 (pattern consistency).

## Technical Details

**Affected files:**
- `Makefile` — Line 22, remove or replace `2>/dev/null`

**Related API behavior:**
- Replicated API returns 409 on duplicate license field creation
- The `replicated api post` CLI exits non-zero on 409 and prints error to stderr
- The `||` operator already catches this — `2>/dev/null` is not needed for the fallback to work

## Acceptance Criteria

- [ ] `make entitlements` with valid credentials and new field: prints success/field JSON
- [ ] `make entitlements` when field already exists: prints "already exists" message
- [ ] `make entitlements` with expired/invalid token: prints a real error, exits non-zero
- [ ] `make entitlements` with network error: prints a real error, exits non-zero

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #65 code review | All 5 agents independently flagged; matches documented anti-pattern |

## Resources

- PR #65: https://github.com/crdant/replicated-salesforce-fulfillment/pull/65
- Past learning: docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md
- Pattern reference: `hack/create-channel` lines 40-43
