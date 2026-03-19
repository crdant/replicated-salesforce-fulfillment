---
status: pending
priority: p2
issue_id: "067"
tags:
  - code-review
  - security
  - logging
dependencies: []
---

# Customer ID logged in System.debug

## Problem Statement

`AssetDownloadedHandler` logs `customer_id` from the webhook payload in a `System.debug()` call at line 64. The `ReplicatedWebhookSubscriber` trigger comment states: "Avoid logging payload or customer data -- debug logs are visible to admins." This is the same class of issue fixed in todo 029 (other handlers) and flagged in todo 060 (CustomerUpdatedHandler).

## Findings

- **Security Sentinel**: PASS on error message leakage (noted customer_id is "already in payload") but institutional policy is stricter
- **Learnings Researcher**: `webhook-receiver-code-review-findings.md` explicitly prohibits logging customer IDs
- **Affected line**: `AssetDownloadedHandler.cls` line 63-64

```apex
System.debug(LoggingLevel.WARN,
    'AssetDownloadedHandler: no Account found for customer_id ' + customerId + ', skipping');
```

## Proposed Solutions

### Option A: Remove customer_id from log message (Recommended)
```apex
System.debug(LoggingLevel.WARN,
    'AssetDownloadedHandler: no Account found for customer_id, skipping');
```
- **Pros**: Matches institutional policy; consistent with trigger comment
- **Cons**: Harder to debug specific events (but can query Account table directly)
- **Effort**: Small (1 line edit)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `AssetDownloadedHandler.cls` line 63-64

## Acceptance Criteria

- [ ] No customer IDs or payload field values in System.debug() calls
- [ ] Operational status message still present

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #92 | Same issue as todo 029, 060; institutional policy clear |

## Resources

- PR #92: https://github.com/crdant/replicated-salesforce-fulfillment/pull/92
- Related: todo 029 (PII in debug logs), todo 060 (CustomerUpdatedHandler)
- `docs/solutions/security-issues/webhook-receiver-code-review-findings.md`
