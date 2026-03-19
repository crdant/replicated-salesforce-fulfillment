---
status: complete
priority: p2
issue_id: "025"
tags:
  - code-review
  - security
  - compliance
  - logging
dependencies: []
---

# PII (email addresses, customer IDs) logged in System.debug

## Problem Statement

The handlers log email addresses and customer IDs in `System.debug()` statements, despite the trigger's own comment at line 4 explicitly warning: "Avoid logging payload or customer data -- debug logs are visible to admins."

This contradicts the stated security intent and creates GDPR/CCPA compliance risk.

This finding was identified by security-sentinel.

## Findings

- **Security Sentinel**: Finding #7 (LOW) — email addresses are PII; customer IDs are sensitive identifiers. Debug logs are visible to any user with "Manage Users" or "View All Data" permissions.
- **Specific locations**:
  - `TrialSignupHandler.cls` line 23: logs email
  - `CustomerCreatedHandler.cls` line 46: logs email
  - `AssetDownloadedHandler.cls` line 24: logs customer ID
  - `AssetDownloadedHandler.cls` line 40: logs customer ID

## Proposed Solutions

### Option A: Remove PII from debug messages (Recommended)
- Keep the operational status messages but strip out identifiers
- Example: `'TrialSignupHandler: Lead already exists, skipping'`
- **Pros**: Matches the trigger's stated intent; eliminates compliance risk
- **Cons**: Harder to debug specific records (but can query directly)
- **Effort**: Small (4 line edits)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: All 3 handler classes (4 debug statements total)

## Acceptance Criteria

- [ ] No email addresses or customer IDs in System.debug() calls
- [ ] Operational status messages still present for debugging

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | Trigger comment already warns about this |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
- `docs/solutions/security-issues/webhook-receiver-code-review-findings.md`
