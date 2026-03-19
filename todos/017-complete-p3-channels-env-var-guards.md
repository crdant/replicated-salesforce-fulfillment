---
status: complete
priority: p3
issue_id: "017"
tags:
  - code-review
  - tooling
  - defensive-coding
dependencies: []
---

# Add environment variable guards to channels target

## Problem Statement

The `channels` Makefile target requires `REPLICATED_APP` and `REPLICATED_CHANNEL` environment variables but does not validate their presence. When unset, the `replicated` CLI produces opaque error messages rather than clear "missing required variable" feedback.

## Findings

**File:** `Makefile:13-18` — No validation before using env vars

**Past incident:** docs/solutions/integration-issues/salesforce-webhook-endpoint-testing-integration.md documents a bug where the `webhook-secret` target used `${ORG_ALIAS}` while other targets hardcoded `shortrib`, causing failures when the variable was unset. Same class of issue.

**Existing pattern:** `hack/set-webhook-secret` validates inputs and prints explicit usage messages. The `channels` target should follow this convention.

## Proposed Solutions

### Option A: Add test guards at top of recipe
```makefile
channels:
	@test -n "$${REPLICATED_APP}" || { echo "Error: REPLICATED_APP is required"; exit 1; }
	@test -n "$${REPLICATED_CHANNEL}" || { echo "Error: REPLICATED_CHANNEL is required"; exit 1; }
	@id=...
```
- **Effort**: Small
- **Risk**: Low

### Option B: Address as part of hack/ script extraction (todo 012)
- If extracting to `hack/create-channel`, add validation there instead
- **Effort**: Small (bundled with 012)
- **Risk**: Low

## Recommended Action

Address as part of todo 012 if that is accepted. Otherwise apply Option A independently.

## Technical Details

**Affected files:**
- `Makefile` — Add guards before channel logic

## Acceptance Criteria

- [ ] `make channels` with unset `REPLICATED_APP` prints clear error and exits 1
- [ ] `make channels` with unset `REPLICATED_CHANNEL` prints clear error and exits 1

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #48 code review | Mirrors past ORG_ALIAS inconsistency bug |

## Resources

- PR #48: https://github.com/crdant/replicated-salesforce-fulfillment/pull/48
- Past learning: docs/solutions/integration-issues/salesforce-webhook-endpoint-testing-integration.md
