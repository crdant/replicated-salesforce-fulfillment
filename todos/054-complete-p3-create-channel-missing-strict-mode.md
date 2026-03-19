---
status: complete
priority: p3
issue_id: "054"
tags:
  - code-review
  - shell-hardening
  - pre-existing
dependencies: []
---

# hack/create-channel missing set -euo pipefail

## Problem Statement

Every `hack/` script in the project uses `set -euo pipefail` except `hack/create-channel`. Since `create-channel` is the first target in the `setup-replicated` orchestrator chain, a failure partway through the script may not halt execution or propagate a nonzero exit code to Make.

This is a pre-existing issue, not introduced by this PR.

## Findings

**File:** `hack/create-channel` — missing `set -euo pipefail`

**Flagged by:** security-sentinel (Minor suggestion), architecture-strategist (Low)

**Evidence:**
- All other `hack/` scripts have `set -euo pipefail`: `setup-enterprise-portal`, `create-license-field`, `setup-webhook-subscription`, `resolve-app-metadata`, `set-api-token`
- `hack/create-channel` lacks it
- Learnings researcher confirmed: `docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md` documents this class of issue

## Proposed Solutions

### Option A: Add set -euo pipefail to hack/create-channel
- **Pros:** Consistent with all other scripts, errors propagate correctly
- **Cons:** May surface previously-silent failures (good, but needs testing)
- **Effort:** Small (1 line)
- **Risk:** Low

## Technical Details

**Affected files:**
- `hack/create-channel`

## Acceptance Criteria

- [ ] `hack/create-channel` includes `set -euo pipefail`
- [ ] All `hack/` scripts consistently use strict mode

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #70 code review | Pre-existing inconsistency |

## Resources

- PR #70: https://github.com/crdant/replicated-salesforce-fulfillment/pull/70
- `docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md`
