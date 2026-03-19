---
status: complete
priority: p2
issue_id: "060"
tags:
  - code-review
  - security
  - logging
dependencies: []
---

# Payload-derived values logged in System.debug

## Problem Statement

`CustomerUpdatedHandler` logs `customer_id` and `dateString` values from webhook payloads in `System.debug()` calls. The `ReplicatedWebhookSubscriber` trigger comment at line 12 explicitly states: "Avoid logging payload or customer data -- debug logs are visible to admins." This is the same class of issue previously fixed in other handlers (todo 029).

This finding was identified by security-sentinel and corroborated by learnings-researcher (referencing `docs/solutions/security-issues/webhook-receiver-code-review-findings.md`).

## Findings

- **Security Sentinel**: Finding #3 (LOW) — `customer_id` logged at line 61; Finding #4 (LOW) — `dateString` logged at line 119
- **Learnings Researcher**: Handler should not log customer IDs or payload contents per established policy
- **Specific locations**:
  - `CustomerUpdatedHandler.cls` line 61: logs `customer_id`
  - `CustomerUpdatedHandler.cls` line 119: logs `dateString`

## Proposed Solutions

### Option A: Remove payload values from log messages (Recommended)
- Keep operational messages but strip identifiers
- `'CustomerUpdatedHandler: no matching Account found, skipping event'`
- `'CustomerUpdatedHandler: failed to parse expires_at date'`
- **Pros**: Matches trigger's stated intent; consistent with todo 029 fixes
- **Cons**: Harder to debug specific records (but can query directly)
- **Effort**: Small (2 line edits)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `CustomerUpdatedHandler.cls` (2 debug statements)

## Acceptance Criteria

- [ ] No customer IDs or payload field values in System.debug() calls
- [ ] Operational status messages still present for debugging

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #89 | Same issue as todo 029; trigger comment warns against this |

## Resources

- PR #89: https://github.com/crdant/replicated-salesforce-fulfillment/pull/89
- Related: todo 029 (PII in debug logs — other handlers)
- `docs/solutions/security-issues/webhook-receiver-code-review-findings.md`
