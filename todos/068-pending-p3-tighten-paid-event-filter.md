---
status: pending
priority: p3
issue_id: "068"
tags:
  - code-review
  - simplicity
  - apex
dependencies: []
---

# Tighten paid-event filter to require non-blank app_id

## Problem Statement

Events with `license_type == 'paid'` are added to `paidEvents` regardless of whether `app_id` exists (line 83-90). The `app_id` is then filtered again inside `fulfillOrders` at line 171. A paid event with blank `app_id` is added to `paidEvents` but will always be skipped in fulfillOrders — a dead code path that adds one loop iteration and a separate filter to reason about.

## Findings

- **Code Simplicity Reviewer**: Recommendation #1 — merge the `app_id` check into the `paid` conditional to eliminate split filtering
- **Net removal**: ~6 lines (3 in execute, 3 in fulfillOrders)

**Location**: `AssetDownloadedHandler.cls` lines 82-90 and 170-173

## Proposed Solutions

### Option A: Require both paid AND non-blank app_id (Recommended)
```apex
String licenseType = (String) data.get('license_type');
String appId = (String) data.get('app_id');
if (licenseType == 'paid' && String.isNotBlank(appId)) {
    paidEvents.add(data);
    paidAccountIds.add(acc.Id);
    paidAppIds.add(appId);
}
```
Then remove the `String.isBlank(appId)` guard in `fulfillOrders` (lines 170-173).
- **Pros**: Eliminates dead code path; single filter point; easier to reason about
- **Cons**: None
- **Effort**: Small (6-line edit)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `AssetDownloadedHandler.cls` lines 82-90, 170-173

## Acceptance Criteria

- [ ] Paid events without app_id are filtered at collection time, not in fulfillOrders
- [ ] `fulfillOrders` does not contain a blank-appId guard

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #92 | Split filtering adds cognitive load |

## Resources

- PR #92: https://github.com/crdant/replicated-salesforce-fulfillment/pull/92
