---
status: complete
priority: p2
issue_id: "028"
tags:
  - code-review
  - architecture
  - data-integrity
  - error-handling
dependencies: []
---

# No Savepoint/rollback in AssetDownloadedHandler multi-DML sequence

## Problem Statement

`AssetDownloadedHandler.createAccountContactOpportunity()` performs 3 sequential `insert` DML operations (Account, Contact, Opportunity). If the Contact or Opportunity insert fails (e.g., validation rule, required field missing), the Account is already committed, leaving an orphan Account with no associated Contact or Opportunity.

This finding was identified by architecture-strategist.

## Findings

- **Architecture Strategist**: "The three sequential DML operations can leave orphaned records if one fails partway through. Wrap them in a Savepoint pattern."

## Proposed Solutions

### Option A: Add Savepoint/rollback (Recommended)
- Wrap the 3 inserts in a `Database.setSavepoint()` / `Database.rollback()` pattern
- **Pros**: Atomic operation; no orphaned records on partial failure
- **Cons**: Adds ~5 lines
- **Effort**: Small
- **Risk**: None

### Option B: Accept current behavior
- Orphan Accounts are unlikely given the simple field requirements
- The handler can be re-run to fill in missing records
- **Pros**: No change
- **Cons**: Data integrity risk on DML failures
- **Effort**: None
- **Risk**: Low (but real)

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `create-license/main/default/classes/AssetDownloadedHandler.cls` (lines 80-104)

## Acceptance Criteria

- [ ] Multi-DML sequence is atomic (all-or-nothing)
- [ ] Failed insert rolls back prior inserts in the sequence

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
