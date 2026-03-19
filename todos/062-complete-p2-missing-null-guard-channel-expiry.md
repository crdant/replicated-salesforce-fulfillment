---
status: complete
priority: p2
issue_id: "062"
tags:
  - code-review
  - data-integrity
  - apex
dependencies: []
---

# Missing null guard on channel_name and expires_at when change flags are true

## Problem Statement

When `channel_changed == true`, the handler writes `data.get('channel_name')` directly to `Account.Replicated_Channel__c` without checking for null (line 86). Similarly for `expires_at` when `expiration_changed == true` (line 93). If Replicated sends a malformed payload with the flag set but the value missing, the handler would blank the Account field. The `customer_name` and `license_type` paths (lines 68-80) already have null guards on both old and new values — this is an inconsistency.

This finding was identified by architecture-strategist.

## Findings

- **Architecture Strategist**: Recommendation #2 — defensive null-check on `channel_name` and `expires_at` when their respective change flags are true
- **Learnings Researcher**: Change detection relies on payload correctness; defensive guards are consistent with the codebase's other handlers

## Proposed Solutions

### Option A: Add null guards (Recommended)
```apex
// Channel: add null check
Boolean channelChanged = (Boolean) data.get('channel_changed');
String channelName = (String) data.get('channel_name');
if (channelChanged == true && channelName != null) {
    acc.Replicated_Channel__c = channelName;
    changed = true;
}

// Expiry: parseDate already returns null for blank strings, so guard the flag
Boolean expirationChanged = (Boolean) data.get('expiration_changed');
if (expirationChanged == true) {
    Date expiryDate = parseDate((String) data.get('expires_at'));
    if (expiryDate != null) {
        acc.Replicated_License_Expiry__c = expiryDate;
        changed = true;
    }
}
```
- **Pros**: Consistent with name/license_type paths; prevents accidental field blanking
- **Cons**: Silently skips if Replicated legitimately sets a field to null
- **Effort**: Small (4-6 line edits)
- **Risk**: Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `CustomerUpdatedHandler.cls` lines 84-95

## Acceptance Criteria

- [ ] `channel_name` null-checked before writing to Account
- [ ] `expires_at` null-checked (or parseDate result) before writing to Account
- [ ] All four field sync paths use consistent null-guard pattern

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #89 | Name/license paths guard; channel/expiry paths don't |

## Resources

- PR #89: https://github.com/crdant/replicated-salesforce-fulfillment/pull/89
