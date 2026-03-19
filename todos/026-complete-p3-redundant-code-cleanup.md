---
status: complete
priority: p3
issue_id: "026"
tags:
  - code-review
  - code-quality
  - simplification
dependencies: []
---

# Remove redundant FirstName = '' and lc.setDoNotCreateOpportunity(false)

## Problem Statement

Minor code cleanup — three lines that do nothing or are misleading:

1. `FirstName = ''` in `TrialSignupHandler.cls` (line 29) and `CustomerCreatedHandler.cls` (line 48): Salesforce stores empty string as null for text fields. Setting it explicitly suggests intentionality where there is none.
2. `lc.setDoNotCreateOpportunity(false)` in `AssetDownloadedHandler.cls` (line 56): `false` is the default value, so this line has no effect.

This finding was identified by code-simplicity-reviewer.

## Proposed Solutions

### Option A: Remove all 3 lines (Recommended)
- Delete `FirstName = ''` from both handlers
- Delete `lc.setDoNotCreateOpportunity(false)` from AssetDownloadedHandler
- **Pros**: Cleaner code; removes cognitive overhead
- **Cons**: None
- **Effort**: Small (3 line deletions)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `TrialSignupHandler.cls` (line 29), `CustomerCreatedHandler.cls` (line 48), `AssetDownloadedHandler.cls` (line 56)

## Acceptance Criteria

- [ ] `FirstName = ''` removed from both handlers
- [ ] `lc.setDoNotCreateOpportunity(false)` removed
- [ ] Tests still pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
