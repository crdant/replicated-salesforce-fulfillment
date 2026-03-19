---
status: complete
priority: p2
issue_id: "061"
tags:
  - code-review
  - reliability
  - apex
dependencies: []
---

# All-or-nothing DML in CustomerUpdatedHandler

## Problem Statement

`CustomerUpdatedHandler` uses bare `update toUpdate` (line 104) which is all-or-nothing DML. A single bad record (validation rule, field length exceeded) rolls back all Account updates in the batch. `CustomerCreatedHandler` already uses `Database.insert(toInsert, dmlOpts)` for partial success, making this an inconsistency.

This finding was identified by security-sentinel.

## Findings

- **Security Sentinel**: Finding #2 (LOW) — bare `update` at line 104; CustomerCreatedHandler uses `Database.insert` with allOrNone=false at line 91
- **Architecture Strategist**: Confirmed inconsistency with existing handler pattern
- The handler processes up to 2,000 events per trigger batch; one bad record blocks all updates

## Proposed Solutions

### Option A: Use Database.update with partial success (Recommended)
- Replace `update toUpdate` with `Database.update(toUpdate, false)`
- Log failed records at WARN level (without payload data per todo 056)
- **Pros**: Consistent with CustomerCreatedHandler; one bad record doesn't block others
- **Cons**: Partial failures are silent unless logged
- **Effort**: Small (3-5 line change)
- **Risk**: Low

### Option B: Keep all-or-nothing
- Accept current behavior; failed batches retry via Platform Event replay
- **Pros**: Simpler; atomicity guarantees
- **Cons**: One bad record blocks entire batch; inconsistent with other handlers
- **Effort**: None
- **Risk**: Low (for small batches)

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `CustomerUpdatedHandler.cls` line 104

## Acceptance Criteria

- [ ] DML uses `Database.update(toUpdate, false)` for partial success
- [ ] Failed records are logged (without payload values)
- [ ] Consistent with CustomerCreatedHandler pattern

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #89 | CustomerCreatedHandler already uses partial success |

## Resources

- PR #89: https://github.com/crdant/replicated-salesforce-fulfillment/pull/89
