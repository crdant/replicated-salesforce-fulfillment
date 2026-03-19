---
status: deferred
priority: p3
issue_id: "075"
github_issue: 97
tags:
  - code-review
  - performance
  - apex
  - governor-limits
dependencies: []
---

# LeadStatus query runs even when no conversions are needed

## Problem Statement

Line 86-90 of `EpUserJoinedHandler.cls` always queries `LeadStatus` to find the converted status label, even when no Leads were found in the preceding queries. This wastes a SOQL query against governor limits in the no-conversion path (direct-create only, or all-accounts-exist skip).

## Proposed Solutions

### Option A: Defer query until conversions are confirmed (Recommended)

Move the `LeadStatus` query inside the `if (!conversions.isEmpty())` block, or query lazily before `Database.convertLead()`.

- Effort: Small
- Risk: None

## Technical Details

- **Affected files**: `create-license/main/default/classes/EpUserJoinedHandler.cls` lines 86-90
- **Database changes**: None

## Acceptance Criteria

- [ ] `LeadStatus` query only runs when conversions exist
- [ ] Existing tests continue to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-19 | Created | Code review finding — code simplicity reviewer |

## Resources

- PR: #91
- File: `EpUserJoinedHandler.cls` lines 86-90
