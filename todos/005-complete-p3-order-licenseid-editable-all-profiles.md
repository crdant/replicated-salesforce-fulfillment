---
status: pending
priority: p3
issue_id: "005"
tags:
  - code-review
  - security
  - pre-existing
dependencies: []
---

# Pre-existing: Order.LicenseId__c is editable=true on all non-Admin profiles

## Problem Statement

`Order.LicenseId__c` stores the generated Replicated license ID and is populated programmatically by the `ReplicatedFulfillment` Queueable class (system context, bypasses FLS). All 6 profiles have `editable=true`, meaning any user can manually modify license IDs through the UI, which could break license reconciliation.

## Findings

- **Security Sentinel**: Not introduced by PR #25 (pre-existing), but flagged as a related concern. Non-Admin profiles should have `editable=false` since the Queueable runs in system context.

## Proposed Solutions

### Option A: Set editable=false on non-Admin profiles
- **Effort**: Small (5 profile changes)
- **Risk**: None — Apex system context bypasses FLS

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Order.LicenseId__c has editable=false on all non-Admin profiles

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-16 | Created from code review of PR #25 | Pre-existing issue; not introduced by this PR |

## Resources

- PR #25: https://github.com/crdant/replicated-salesforce-fulfillment/pull/25
- `ReplicatedFulfillment.cls` line 21: where LicenseId__c is set
