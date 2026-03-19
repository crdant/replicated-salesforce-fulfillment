---
status: pending
priority: p2
issue_id: "065"
tags:
  - code-review
  - data-integrity
  - apex
dependencies: []
---

# parseDateTime silently falls back to DateTime.now() on bad input

## Problem Statement

`AssetDownloadedHandler.parseDateTime` returns `DateTime.now()` when `downloaded_at` is blank or unparseable, with no logging on the catch path. This silently records fabricated timestamps on both `Replicated_Download__c.Downloaded_At__c` and `Order.FulfilledAt__c`. The existing `InstanceEventHandler.parseDateTime` returns `null` on failure and logs a warning — the two handlers use inconsistent fallback strategies for the same operation.

For download records, an approximate timestamp is acceptable. For `FulfilledAt__c`, stamping the processing time instead of the actual download time could affect fulfillment reporting and revenue-recognition workflows.

## Findings

- **Security Sentinel**: Finding #1 (MEDIUM) — silent coercion to DateTime.now() is a data integrity risk
- **Architecture Strategist**: Finding 4a (LOW) — inconsistent with InstanceEventHandler pattern
- **Agent-Native Reviewer**: Warning #1 — should log at WARN when fallback is used
- **Learnings Researcher**: CustomerUpdatedHandler hardening (docs/solutions) established that handler inconsistencies should be corrected

**Location**: `AssetDownloadedHandler.cls` lines 193-202

## Proposed Solutions

### Option A: Add WARN logging to catch block (Recommended)
- Keep `DateTime.now()` fallback but make it observable
- Matches the logging discipline in the rest of the handler
```apex
} catch (Exception e) {
    System.debug(LoggingLevel.WARN,
        'AssetDownloadedHandler: could not parse downloaded_at, using current time');
    return DateTime.now();
}
```
- **Pros**: Minimal change; makes the fallback visible in debug logs; preserves required-field safety
- **Cons**: Still records inaccurate timestamps
- **Effort**: Small (2-line edit)
- **Risk**: None

### Option B: Return null on failure, let caller decide
- Align with InstanceEventHandler pattern
- Callers set `DateTime.now()` explicitly with a log, or skip the field
- **Pros**: Consistent across handlers; callers make informed decision
- **Cons**: `Downloaded_At__c` requires a value if the field becomes required; need null guard at call sites
- **Effort**: Small (5-10 line edit)
- **Risk**: Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `AssetDownloadedHandler.cls` lines 193-202
- **Called from**: line 68 (download record creation) and line 181 (order fulfillment)

## Acceptance Criteria

- [ ] Parse failures are logged at WARN level
- [ ] Fallback behavior is documented or aligned with InstanceEventHandler

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #92 | Same parseDateTime exists in InstanceEventHandler with different fallback |

## Resources

- PR #92: https://github.com/crdant/replicated-salesforce-fulfillment/pull/92
- Related: todo 064 (extract shared parseDate utility)
- `InstanceEventHandler.cls` lines 106-117 (null-returning variant)
