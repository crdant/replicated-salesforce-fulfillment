---
status: pending
priority: p2
issue_id: "066"
tags:
  - code-review
  - reliability
  - apex
dependencies: []
---

# All-or-nothing DML in AssetDownloadedHandler

## Problem Statement

`AssetDownloadedHandler` uses bare `insert downloads` (line 96) and bare `update toUpdate` (line 189). A single bad record (field validation failure, length exceeded) rolls back the entire batch. This is the same pattern flagged in todo 061 for CustomerUpdatedHandler.

For download inserts: one malformed record blocks 199 good ones from being recorded. For order updates: one validation rule failure blocks all order fulfillments in the batch.

## Findings

- **Architecture Strategist**: Recommendation 5a — use `Database.insert(downloads, false)` matching CustomerUpdatedHandler pattern
- **Learnings Researcher**: CustomerUpdatedHandler hardening established `Database.update(toUpdate, false)` as the standard; same applies here
- **Security Sentinel**: Finding #3 context — 2,000-event batches amplify the blast radius of all-or-nothing DML

**Locations**:
- `AssetDownloadedHandler.cls` line 96: `insert downloads`
- `AssetDownloadedHandler.cls` line 189: `update toUpdate`

## Proposed Solutions

### Option A: Use partial-success DML with failure logging (Recommended)
```apex
// Downloads
List<Database.SaveResult> results = Database.insert(downloads, false);
for (Database.SaveResult result : results) {
    if (!result.isSuccess()) {
        System.debug(LoggingLevel.WARN,
            'AssetDownloadedHandler: failed to insert download record: ' +
            result.getErrors()[0].getMessage());
    }
}

// Orders
List<Database.SaveResult> orderResults = Database.update(toUpdate, false);
for (Database.SaveResult result : orderResults) {
    if (!result.isSuccess()) {
        System.debug(LoggingLevel.WARN,
            'AssetDownloadedHandler: failed to update Order: ' +
            result.getErrors()[0].getMessage());
    }
}
```
- **Pros**: One bad record doesn't block others; consistent with CustomerCreatedHandler pattern; failure logging aids debugging
- **Cons**: Partial failures are silent beyond debug logs
- **Effort**: Small (10-line change)
- **Risk**: Low

### Option B: Keep all-or-nothing
- Accept current behavior; failed batches retry via Platform Event replay
- **Pros**: Simpler; atomicity guarantees
- **Cons**: One bad record blocks entire batch
- **Effort**: None
- **Risk**: Low for small batches, high for 2,000-event batches

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `AssetDownloadedHandler.cls` lines 96, 189

## Acceptance Criteria

- [ ] Download insert uses `Database.insert(downloads, false)`
- [ ] Order update uses `Database.update(toUpdate, false)`
- [ ] Failed records logged at WARN level (without payload values)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #92 | Same pattern as todo 061 (CustomerUpdatedHandler) |

## Resources

- PR #92: https://github.com/crdant/replicated-salesforce-fulfillment/pull/92
- Related: todo 061 (all-or-nothing DML in CustomerUpdatedHandler)
- `docs/solutions/integration-issues/hardening-customer-updated-handler.md`
