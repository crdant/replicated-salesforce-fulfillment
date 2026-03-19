---
status: complete
priority: p3
issue_id: "064"
tags:
  - code-review
  - simplicity
  - duplication
  - apex
dependencies: []
---

# Duplicated parseDate method across 3+ handlers

## Problem Statement

The `parseDate` private static method is now copied in `CustomerUpdatedHandler`, `CustomerCreatedHandler`, and `LicenseExpiringHandler` (with `InstanceEventHandler` having a similar `parseDateTime`). All copies are byte-for-byte identical in logic. A change to date parsing logic would need to be applied in 3-4 places.

This is a pre-existing pattern — this PR just adds another copy. Multiple agents flagged it.

## Findings

- **Architecture Strategist**: Recommendation #1 — extract to shared `ReplicatedDateParser` or `WebhookPayloadUtils` utility class
- **Code Simplicity Reviewer**: Same finding; suggests extracting when a fourth handler needs it (rule of three — already exceeded)
- **Agent-Native Reviewer**: Single utility would be easier for automated refactoring tools to maintain

## Proposed Solutions

### Option A: Extract to shared utility class (Recommended)
```apex
public class WebhookPayloadUtils {
    public static Date parseDate(String dateString) { ... }
}
```
- **Pros**: Single source of truth; ~30 lines saved across codebase
- **Cons**: Requires touching 3 existing handlers
- **Effort**: Small-Medium (new class + 3 handler edits + test verification)
- **Risk**: Low

### Option B: Leave as-is
- **Pros**: No cross-cutting change; each handler is self-contained
- **Cons**: Duplication continues to grow with new handlers
- **Effort**: None
- **Risk**: None

## Recommended Action

<!-- Fill during triage — consider as separate chore PR, not blocking this PR -->

## Technical Details

- **Affected files**: `CustomerUpdatedHandler.cls`, `CustomerCreatedHandler.cls`, `LicenseExpiringHandler.cls`, `InstanceEventHandler.cls`

## Acceptance Criteria

- [ ] Single `parseDate` method in a shared utility class
- [ ] All handlers call the shared method
- [ ] All existing tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #89 | Pre-existing duplication; rule of three exceeded |

## Resources

- PR #89: https://github.com/crdant/replicated-salesforce-fulfillment/pull/89
