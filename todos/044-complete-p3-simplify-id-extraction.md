---
status: complete
priority: p3
issue_id: "044"
tags:
  - code-review
  - quality
  - simplification
dependencies: []
---

# Simplify API response ID extraction in setup-webhook-subscription

## Problem Statement

The script speculatively tries two JSON paths (`.subscription.id // .id // empty`) and has a 6-line fallback block that prints raw JSON if neither path yields an ID. This is defensive coding for an unknown API response shape. Pick the one correct path and remove the fallback.

## Findings

**File:** `hack/setup-webhook-subscription:46-53`

```bash
id=$(echo "$result" | jq -r '.subscription.id // .id // empty')

if [ -n "$id" ]; then
    echo "Created subscription \"${SUBSCRIPTION_NAME}\" (id: ${id})."
else
    echo "Created subscription \"${SUBSCRIPTION_NAME}\"."
    echo "$result" | jq .
fi
```

The dual-path extraction and fallback pretty-print add 4 unnecessary lines. Test the actual API response once and commit to the correct path.

## Proposed Solutions

### Option A: Use the correct single path (Recommended)
```bash
result=$(replicated api post /v3/notification_subscription -b "$body")
id=$(echo "$result" | jq -r '.subscription.id')
echo "Created subscription \"${SUBSCRIPTION_NAME}\" (id: ${id})."
```
- **Effort**: Small
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] ID extraction uses a single known-correct JSON path
- [ ] Fallback branch removed

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #67 code review | Verify actual API response shape before choosing path |

## Resources

- PR: https://github.com/crdant/replicated-salesforce-fulfillment/pull/67
- File: `hack/setup-webhook-subscription`
