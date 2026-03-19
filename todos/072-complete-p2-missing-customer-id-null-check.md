---
status: complete
priority: p2
issue_id: "072"
tags:
  - code-review
  - data-integrity
  - apex
  - validation
dependencies: []
---

# Missing customer_id null/blank check creates orphaned records

## Problem Statement

Line 99 of `EpUserJoinedHandler.cls` casts `data.get('customer_id')` to String without a null/blank check. A null `customerId` passes the idempotency check at line 103 (`existingAccountCustomerIds.contains(null)` returns `false`), bypasses both Lead lookups (neither map contains a null key), and falls through to the direct-create path — creating an Account with a null `Replicated_Customer_Id__c`.

This breaks the project's reconciliation key contract: `Replicated_Customer_Id__c` is the bidirectional join key between Replicated and Salesforce.

## Findings

- **Security Sentinel**: Flagged as Low severity — creates orphaned records that cannot be reconciled.
- **Learnings Researcher**: The hardening patterns in todo #062 establish null-guarding for all field writes. Other handlers (e.g., `TrialSignupHandler`) skip events with blank key fields.

## Proposed Solutions

### Option A: Skip events with blank customer_id (Recommended)

```apex
String customerId = (String) data.get('customer_id');
if (String.isBlank(customerId)) {
    System.debug(LoggingLevel.WARN, 'EpUserJoinedHandler: blank customer_id, skipping');
    continue;
}
```

- Pros: Matches `TrialSignupHandler` pattern; prevents orphaned records
- Cons: None
- Effort: Small (3 lines)
- Risk: None — events without customer_id are invalid per the Replicated API contract

## Recommended Action

Option A.

## Technical Details

- **Affected files**: `create-license/main/default/classes/EpUserJoinedHandler.cls` line 99
- **Affected components**: Per-event processing loop
- **Database changes**: None

## Acceptance Criteria

- [ ] Events with null/blank `customer_id` are skipped with a warning log
- [ ] Add test: event with blank `customer_id` produces no records
- [ ] Existing tests continue to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-19 | Created | Code review finding — security sentinel |

## Resources

- PR: #91
- File: `EpUserJoinedHandler.cls` line 99
- Related: todo #026 (null email bypasses idempotency — same class of bug)
