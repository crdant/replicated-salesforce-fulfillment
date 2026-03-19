---
status: complete
priority: p3
issue_id: "049"
tags:
  - code-review
  - simplicity
  - observability
dependencies: []
---

# verify-replicated discards useful resolve-app-metadata JSON output

## Problem Statement

`verify-replicated` runs `hack/resolve-app-metadata > /dev/null && echo "Channel and app verified."` — it discards the JSON output (`app_name`, `app_id`, `channel_id`) and prints a generic success message. This throws away information the operator could use to confirm the *right* app and channel were resolved. The script's own output is self-documenting verification.

## Findings

**File:** `Makefile:34` — `@hack/resolve-app-metadata > /dev/null && echo "Channel and app verified."`

**Flagged by simplicity reviewer:** "The JSON output *is* the verification. If it succeeds, you see the resolved metadata. If it fails, `set -euo pipefail` ensures a nonzero exit."

## Proposed Solutions

### Option A: Remove output suppression
```makefile
verify-replicated:
	@hack/resolve-app-metadata
```
- **Effort**: Small
- **Risk**: Low
- **Pros**: Simpler, more informative, script output serves as verification
- **Cons**: Slightly more verbose output

## Recommended Action

Option A — let the script speak for itself.

## Technical Details

**Affected files:**
- `Makefile` — Line 34

## Acceptance Criteria

- [ ] `make verify-replicated` shows resolved app_name, app_id, and channel_id

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #69 code review | |

## Resources

- PR #69: https://github.com/crdant/replicated-salesforce-fulfillment/pull/69
