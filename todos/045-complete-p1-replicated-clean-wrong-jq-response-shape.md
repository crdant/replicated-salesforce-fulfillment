---
status: complete
priority: p1
issue_id: "045"
tags:
  - code-review
  - bug
  - jq
  - replicated-api
dependencies: []
---

# replicated-clean uses wrong jq response shape — target is silently non-functional

## Problem Statement

The `replicated-clean` Makefile target parses the Replicated API response with `.[]` (bare array iteration), but `hack/setup-webhook-subscription` parses the same endpoint's response with `.subscriptions // []`. The API returns `{"subscriptions": [...]}`, not a bare array. This means `.[]` iterates over the object's top-level keys (producing the string `"subscriptions"`), the `select(.name == "Salesforce CRM Sync")` never matches, and the `while read` loop never executes. The target silently does nothing.

## Findings

**File:** `Makefile:42` — `.[]` should be `.subscriptions // [] | .[]`

**Evidence from `hack/setup-webhook-subscription` line 13-15:**
```bash
existing=$(replicated api get /v3/notification_subscriptions | \
  jq -e --arg name "$SUBSCRIPTION_NAME" \
    '.subscriptions // [] | map(select(.name == $name)) | first // empty' 2>/dev/null) || true
```

The same API endpoint (`/v3/notification_subscriptions`) returns `{"subscriptions": [...]}`, requiring `.subscriptions` to access the array. The Makefile target omits this and iterates on the bare object, which produces key names not subscription objects.

**Agent-native reviewer flagged this as likely bug that makes the target non-functional.**

## Proposed Solutions

### Option A: Fix the jq expression inline
- Change `.[]` to `.subscriptions // [] | .[]` in the Makefile.
- **Effort**: Small (edit one line)
- **Risk**: Low
- **Pros**: Minimal change, fixes the bug
- **Cons**: Inline logic in Makefile remains; subscription name still duplicated

### Option B: Extract to `hack/clean-webhook-subscription` script
- Move the logic to a proper script with `set -euo pipefail`, correct jq expression, and shared subscription name constant.
- **Effort**: Medium
- **Risk**: Low
- **Pros**: Fixes bug, follows delegation pattern, eliminates duplicated subscription name, adds proper error handling
- **Cons**: Adds a new file

## Recommended Action

Option B — extract to a script. This fixes the bug while also addressing the pattern violation (finding 046) and the duplicated subscription name.

## Technical Details

**Affected files:**
- `Makefile` — Lines 39-43, `replicated-clean` target
- `hack/setup-webhook-subscription` — Line 10, defines `SUBSCRIPTION_NAME="Salesforce CRM Sync"`

**API response shape:**
```json
{"subscriptions": [{"id": "abc123", "name": "Salesforce CRM Sync", ...}]}
```

## Acceptance Criteria

- [ ] `make replicated-clean` with an existing "Salesforce CRM Sync" subscription: prints deletion confirmation, subscription is removed
- [ ] `make replicated-clean` with no matching subscription: prints "no subscription found" or similar
- [ ] `make replicated-clean` with API auth failure: prints error, exits non-zero

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #69 code review | Agent-native reviewer caught mismatch between Makefile jq and setup-webhook-subscription jq |

## Resources

- PR #69: https://github.com/crdant/replicated-salesforce-fulfillment/pull/69
- Reference: `hack/setup-webhook-subscription` lines 13-15
