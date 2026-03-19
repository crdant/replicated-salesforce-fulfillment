---
status: complete
priority: p3
issue_id: "063"
tags:
  - code-review
  - simplicity
  - apex
dependencies: []
---

# SOQL query selects 4 unused fields

## Problem Statement

The SOQL query at lines 46-52 of `CustomerUpdatedHandler.cls` selects `Name`, `Replicated_License_Type__c`, `Replicated_Channel__c`, and `Replicated_License_Expiry__c`, but the handler never reads these values from the queried Account records. Change detection uses the payload's `old_*` and `*_changed` fields exclusively. Only `Id` and `Replicated_Customer_Id__c` are actually used.

This finding was identified by code-simplicity-reviewer.

## Findings

- **Code Simplicity Reviewer**: The SOQL could be `SELECT Id, Replicated_Customer_Id__c FROM Account WHERE ...` — removes false impression that current DB values are compared

## Proposed Solutions

### Option A: Trim SOQL to used fields only (Recommended)
```apex
SELECT Id, Replicated_Customer_Id__c
FROM Account
WHERE Replicated_Customer_Id__c IN :customerIds
```
- **Pros**: Clearer intent; marginally more efficient
- **Cons**: None
- **Effort**: Small (1 line edit)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `CustomerUpdatedHandler.cls` lines 46-48

## Acceptance Criteria

- [ ] SOQL only selects `Id` and `Replicated_Customer_Id__c`
- [ ] All tests still pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #89 | Handler uses payload change-tracking, not DB comparison |

## Resources

- PR #89: https://github.com/crdant/replicated-salesforce-fulfillment/pull/89
