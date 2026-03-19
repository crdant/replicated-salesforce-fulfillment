---
status: complete
priority: p2
issue_id: "073"
tags:
  - code-review
  - reliability
  - apex
  - dml
dependencies: []
---

# enrichConvertedAccounts uses all-or-nothing update

## Problem Statement

Line 175 of `EpUserJoinedHandler.cls` uses bare `update toUpdate` for Account enrichment after Lead conversion. This is all-or-nothing DML — if one Account enrichment fails (e.g., a validation rule on `Replicated_License_Type__c`), ALL enrichments in the batch fail. Successfully converted Leads would have their Accounts exist but without the Replicated custom fields carried over.

The established hardening pattern (from previous code review todo #061) recommends `Database.update(list, false)` for partial success in webhook handlers.

## Findings

- **Security Sentinel**: Flagged as Low (batch rollback behavior). One bad record silently drops enrichment for all records.
- **Learnings Researcher**: Todo #061 (all-or-nothing DML semantics) established `Database.update(list, false)` as the standard for webhook handlers. `CustomerUpdatedHandler` already uses this pattern.

## Proposed Solutions

### Option A: Use partial-success DML with error logging (Recommended)

```apex
if (!toUpdate.isEmpty()) {
    List<Database.SaveResult> results = Database.update(toUpdate, false);
    for (Integer i = 0; i < results.size(); i++) {
        if (!results[i].isSuccess()) {
            System.debug(LoggingLevel.ERROR,
                'EpUserJoinedHandler: Account enrichment failed');
        }
    }
}
```

- Pros: One failure doesn't block other enrichments; matches established pattern
- Cons: Slightly more code
- Effort: Small
- Risk: None

## Recommended Action

Option A.

## Technical Details

- **Affected files**: `create-license/main/default/classes/EpUserJoinedHandler.cls` line 175
- **Affected components**: Post-conversion Account enrichment
- **Database changes**: None

## Acceptance Criteria

- [ ] `update` replaced with `Database.update(toUpdate, false)`
- [ ] Failed enrichments logged individually without crashing the batch
- [ ] Existing tests continue to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-19 | Created | Code review finding — security sentinel + learnings researcher |

## Resources

- PR: #91
- File: `EpUserJoinedHandler.cls` line 175
- Related: todo #061 (all-or-nothing DML semantics)
